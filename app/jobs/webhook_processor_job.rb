# frozen_string_literal: true

class WebhookProcessorJob < ApplicationJob
  queue_as :webhooks
  
  # Retry failed jobs with exponential backoff
  retry_on StandardError, wait: :polynomially_longer, attempts: 3
  
  def perform(webhook_event_id)
    webhook_event = WebhookEvent.find(webhook_event_id)
    
    # Skip if already processed
    return if webhook_event.status == 'processed'
    
    # Mark as processing
    webhook_event.mark_processing!
    
    # Route to appropriate handler based on event type
    handler = find_handler_for(webhook_event.event_type)
    
    if handler
      handler.new(webhook_event).process
      webhook_event.mark_processed!
    else
      Rails.logger.info "No handler for event type: #{webhook_event.event_type}"
      webhook_event.mark_skipped!("No handler configured for #{webhook_event.event_type}")
    end
  rescue => e
    Rails.logger.error "Failed to process webhook event #{webhook_event_id}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    
    webhook_event.mark_failed!(e.message)
    
    # Re-raise to trigger retry if applicable
    raise if webhook_event.should_retry?
  end
  
  private
  
  def find_handler_for(event_type)
    case event_type
    when /^fine_tuning\.job\./
      Webhooks::Handlers::FineTuningHandler
    when /^batch\./
      Webhooks::Handlers::BatchHandler
    when /^response\./
      Webhooks::Handlers::ResponseHandler
    else
      nil
    end
  end
end