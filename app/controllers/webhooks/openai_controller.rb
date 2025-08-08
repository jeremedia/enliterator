# frozen_string_literal: true

module Webhooks
  class OpenaiController < ApplicationController
    # Skip CSRF protection for webhook endpoints
    skip_before_action :verify_authenticity_token
    
    # Main webhook endpoint
    def receive
      # Verify the webhook signature
      unless verify_signature
        Rails.logger.warn "Invalid webhook signature from #{request.remote_ip}"
        head :bad_request
        return
      end
      
      # Store the webhook event
      webhook_event = WebhookEvent.create_from_request!(request.headers, request.body.read)
      
      # Process the webhook asynchronously
      WebhookProcessorJob.perform_later(webhook_event.id)
      
      # Respond immediately with success
      head :ok
    rescue JSON::ParserError => e
      Rails.logger.error "Invalid JSON in webhook payload: #{e.message}"
      head :bad_request
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "Failed to create webhook event: #{e.message}"
      head :unprocessable_entity
    rescue => e
      Rails.logger.error "Webhook processing error: #{e.class} - #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      head :internal_server_error
    end
    
    private
    
    def verify_signature
      # Get the webhook secret from environment or use the known value as fallback
      webhook_secret = ENV['OPENAI_WEBHOOK_SECRET']
      
      if webhook_secret.blank?
        Rails.logger.error "OPENAI_WEBHOOK_SECRET not configured"
        return false
      end
      
      # OpenAI gem doesn't have webhooks method in v0.16.0, use manual verification
      verify_signature_manually(webhook_secret)
    end
    
    def verify_signature_manually(webhook_secret)
      # Extract required headers - they come with HTTP_ prefix in Rails
      webhook_id = request.headers['HTTP_WEBHOOK_ID']
      webhook_timestamp = request.headers['HTTP_WEBHOOK_TIMESTAMP']
      webhook_signature = request.headers['HTTP_WEBHOOK_SIGNATURE']
      
      if webhook_id.blank? || webhook_timestamp.blank? || webhook_signature.blank?
        Rails.logger.warn "Missing required webhook headers"
        Rails.logger.warn "Available headers: #{request.headers.to_h.select { |k, v| k.start_with?('HTTP_') }.keys.join(', ')}"
        return false
      end
      
      # Check timestamp to prevent replay attacks (must be within 5 minutes)
      begin
        timestamp = webhook_timestamp.to_i
        current_time = Time.now.to_i
        
        if (current_time - timestamp).abs > 300
          Rails.logger.warn "Webhook timestamp too old or in future"
          return false
        end
      rescue
        Rails.logger.warn "Invalid webhook timestamp"
        return false
      end
      
      # Construct the signed content according to Standard Webhooks spec
      signed_content = "#{webhook_id}.#{webhook_timestamp}.#{request.body.read}"
      request.body.rewind
      
      # Extract the secret key (remove 'whsec_' prefix if present)
      secret_key = webhook_secret.sub(/^whsec_/, '')
      
      # Calculate the expected signature
      expected_signature = Base64.strict_encode64(
        OpenSSL::HMAC.digest('SHA256', Base64.strict_decode64(secret_key), signed_content)
      )
      
      # Extract signatures from header (format: "v1,signature1 v1,signature2")
      signatures = webhook_signature.split(' ').map do |sig|
        sig.split(',')[1] if sig.start_with?('v1,')
      end.compact
      
      # Verify at least one signature matches
      signatures.any? { |sig| secure_compare(sig, expected_signature) }
    end
    
    def secure_compare(a, b)
      return false unless a.bytesize == b.bytesize
      
      # Constant time comparison to prevent timing attacks
      l = a.unpack("C*")
      r = 0
      b.each_byte.with_index { |v, i| r |= v ^ l[i] }
      r == 0
    end
  end
end