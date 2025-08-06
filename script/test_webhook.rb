#!/usr/bin/env ruby
# Test webhook implementation with a sample payload

require 'net/http'
require 'json'
require 'openssl'
require 'base64'
require 'time'

class WebhookTester
  def initialize
    @webhook_url = 'http://localhost:3000/webhooks/openai'
    @webhook_secret = ENV['OPENAI_WEBHOOK_SECRET'] || 'whsec_vgYpo3DivabKNmnCpncFefzwo03hJgCbpKpOI8jpKNU='
  end
  
  def test_fine_tuning_webhook
    # Sample fine-tuning job succeeded payload
    payload = {
      object: 'event',
      id: 'evt_test_' + SecureRandom.hex(16),
      type: 'fine_tuning.job.succeeded',
      created_at: Time.now.to_i,
      data: {
        id: 'ftjob-BAYr9yRoRKsGlkIviuGfPL2E',
        object: 'fine_tuning.job',
        model: 'gpt-4.1-mini-2025-04-14',
        created_at: Time.now.to_i - 3600,
        finished_at: Time.now.to_i,
        fine_tuned_model: 'ft:gpt-4.1-mini-2025-04-14:enliterator::' + SecureRandom.hex(8),
        organization_id: 'org-test',
        result_files: ['file-' + SecureRandom.hex(12)],
        status: 'succeeded',
        validation_file: nil,
        training_file: 'file-' + SecureRandom.hex(12),
        hyperparameters: {
          n_epochs: 3,
          batch_size: 1,
          learning_rate_multiplier: 2.0
        },
        trained_tokens: 127438,
        error: nil
      }
    }
    
    send_webhook(payload)
  end
  
  def test_batch_webhook
    payload = {
      object: 'event',
      id: 'evt_test_' + SecureRandom.hex(16),
      type: 'batch.completed',
      created_at: Time.now.to_i,
      data: {
        id: 'batch_' + SecureRandom.hex(16),
        object: 'batch',
        endpoint: '/v1/embeddings',
        errors: nil,
        input_file_id: 'file-' + SecureRandom.hex(12),
        completion_window: '24h',
        status: 'completed',
        output_file_id: 'file-' + SecureRandom.hex(12),
        error_file_id: nil,
        created_at: Time.now.to_i - 7200,
        in_progress_at: Time.now.to_i - 3600,
        expires_at: Time.now.to_i + 86400,
        finalizing_at: Time.now.to_i - 300,
        completed_at: Time.now.to_i,
        failed_at: nil,
        expired_at: nil,
        cancelling_at: nil,
        cancelled_at: nil,
        request_counts: {
          total: 1000,
          completed: 998,
          failed: 2
        },
        metadata: {}
      }
    }
    
    send_webhook(payload)
  end
  
  def test_response_webhook
    payload = {
      object: 'event',
      id: 'evt_test_' + SecureRandom.hex(16),
      type: 'response.completed',
      created_at: Time.now.to_i,
      data: {
        id: 'resp_' + SecureRandom.hex(16),
        object: 'response',
        created_at: Time.now.to_i - 60,
        model: 'gpt-4.1',
        usage: {
          prompt_tokens: 150,
          completion_tokens: 250,
          total_tokens: 400
        }
      }
    }
    
    send_webhook(payload)
  end
  
  private
  
  def send_webhook(payload)
    puts "Sending webhook: #{payload[:type]}"
    
    # Generate webhook headers
    webhook_id = 'msg_' + SecureRandom.hex(16)
    webhook_timestamp = Time.now.to_i.to_s
    
    # Create signature
    signature = create_signature(webhook_id, webhook_timestamp, payload.to_json)
    
    # Send HTTP request
    uri = URI(@webhook_url)
    http = Net::HTTP.new(uri.host, uri.port)
    
    request = Net::HTTP::Post.new(uri.path)
    request['Content-Type'] = 'application/json'
    request['webhook-id'] = webhook_id
    request['webhook-timestamp'] = webhook_timestamp
    request['webhook-signature'] = signature
    request['user-agent'] = 'OpenAI/1.0 (+https://platform.openai.com/docs/webhooks)'
    request.body = payload.to_json
    
    begin
      response = http.request(request)
      
      if response.code == '200'
        puts "✅ Webhook sent successfully (#{response.code})"
      else
        puts "❌ Webhook failed (#{response.code}): #{response.body}"
      end
      
      # Check if event was stored
      sleep 1 # Give it a moment to process
      check_stored_event(payload[:id])
      
    rescue => e
      puts "❌ Error sending webhook: #{e.message}"
    end
  end
  
  def create_signature(webhook_id, timestamp, body)
    # Extract the secret key (remove 'whsec_' prefix)
    secret_key = @webhook_secret.sub(/^whsec_/, '')
    
    # Create the signed content
    signed_content = "#{webhook_id}.#{timestamp}.#{body}"
    
    # Calculate signature
    signature = Base64.strict_encode64(
      OpenSSL::HMAC.digest('SHA256', Base64.strict_decode64(secret_key), signed_content)
    )
    
    "v1,#{signature}"
  end
  
  def check_stored_event(event_id)
    event = WebhookEvent.find_by(event_id: event_id)
    
    if event
      puts "✅ Event stored in database:"
      puts "   ID: #{event.event_id}"
      puts "   Type: #{event.event_type}"
      puts "   Status: #{event.status}"
      puts "   Resource: #{event.resource_type} #{event.resource_id}"
    else
      puts "⚠️  Event not found in database"
    end
  end
end

# Run tests
puts "Testing OpenAI Webhook Implementation"
puts "=" * 50

tester = WebhookTester.new

puts "\n1. Testing fine-tuning webhook:"
tester.test_fine_tuning_webhook

puts "\n2. Testing batch webhook:"
tester.test_batch_webhook

puts "\n3. Testing response webhook:"
tester.test_response_webhook

puts "\n" + "=" * 50
puts "Webhook testing complete!"

# Check all stored events
puts "\nStored webhook events:"
WebhookEvent.recent.limit(5).each do |event|
  puts "- #{event.event_type} (#{event.status}) - #{event.created_at}"
end