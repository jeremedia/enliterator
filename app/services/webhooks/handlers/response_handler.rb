# frozen_string_literal: true

module Webhooks
  module Handlers
    class ResponseHandler < BaseHandler
      def process
        case event_type
        when 'response.completed'
          handle_response_completed
        when 'response.failed'
          handle_response_failed
        else
          log_info "Unhandled response event type: #{event_type}"
        end
      end
      
      private
      
      def handle_response_completed
        response_id = data['id']
        log_info "Response completed: #{response_id}"
        
        # Fetch and process the response if needed
        if should_fetch_response?
          fetch_and_process_response(response_id)
        end
        
        # Update metadata
        update_metadata('response_id', response_id)
        update_metadata('completed_at', Time.current.iso8601)
        update_metadata('status', 'completed')
        
        # Send notification
        notify_response_completed(response_id)
      end
      
      def handle_response_failed
        response_id = data['id']
        error = data['error']
        
        log_error "Response failed: #{response_id}"
        log_error "Error: #{error}"
        
        # Update metadata
        update_metadata('response_id', response_id)
        update_metadata('failed_at', Time.current.iso8601)
        update_metadata('error', error)
        update_metadata('status', 'failed')
        
        # Handle failure
        handle_response_failure(response_id, error)
        
        # Send notification
        notify_response_failed(response_id, error)
      end
      
      def should_fetch_response?
        # Determine if we should automatically fetch the response
        # This could be based on configuration or response metadata
        true
      end
      
      def fetch_and_process_response(response_id)
        log_info "Fetching response #{response_id}"
        
        begin
          # Use the OpenAI client to fetch the response
          response = OPENAI.responses.retrieve(response_id)
          
          # Extract the output text
          output_text = extract_output_text(response)
          
          # Store the response content
          update_metadata('output_text', output_text)
          update_metadata('output_length', output_text.length)
          
          # Process the response based on its context
          process_response_content(response_id, output_text)
          
          log_info "Successfully processed response #{response_id}"
        rescue => e
          log_error "Failed to fetch response #{response_id}: #{e.message}"
          raise
        end
      end
      
      def extract_output_text(response)
        # Extract text from the response output structure
        output_items = response.output || []
        
        text_parts = output_items
          .select { |item| item['type'] == 'message' }
          .flat_map { |item| item['content'] || [] }
          .select { |content| content['type'] == 'output_text' }
          .map { |content| content['text'] }
        
        text_parts.join("\n")
      end
      
      def process_response_content(response_id, output_text)
        # Process the response content based on its purpose
        # This could involve:
        # - Storing in database
        # - Triggering follow-up actions
        # - Updating related records
        
        # Example: If this was a response for generating deliverables
        if webhook_event.metadata['purpose'] == 'deliverable_generation'
          store_deliverable(response_id, output_text)
        end
      end
      
      def store_deliverable(response_id, content)
        log_info "Storing deliverable from response #{response_id}"
        
        # Store the generated deliverable
        # This would depend on your specific deliverable model
        if defined?(::GeneratedDeliverable)
          ::GeneratedDeliverable.create!(
            response_id: response_id,
            content: content,
            metadata: {
              generated_at: Time.current.iso8601,
              webhook_event_id: webhook_event.id
            }
          )
        end
      end
      
      def handle_response_failure(response_id, error)
        # Handle response failure
        # Could involve:
        # - Retrying the request
        # - Notifying relevant parties
        # - Updating related records
        
        if should_retry_response?(error)
          log_info "Scheduling retry for response #{response_id}"
          
          # Queue retry job if available
          if defined?(::ResponseRetryJob)
            ::ResponseRetryJob.perform_later(response_id, webhook_event.metadata)
          end
        end
      end
      
      def should_retry_response?(error)
        # Determine if we should retry based on error type
        retryable_errors = ['timeout', 'rate_limit', 'temporary_failure']
        
        error_type = error['type'] || error['code']
        retryable_errors.include?(error_type)
      end
      
      # Notification methods
      
      def notify_response_completed(response_id)
        log_info "NOTIFICATION: Response #{response_id} completed successfully"
      end
      
      def notify_response_failed(response_id, error)
        log_error "NOTIFICATION: Response #{response_id} failed: #{error}"
      end
    end
  end
end