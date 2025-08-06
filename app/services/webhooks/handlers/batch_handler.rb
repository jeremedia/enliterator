# frozen_string_literal: true

module Webhooks
  module Handlers
    class BatchHandler < BaseHandler
      def process
        case event_type
        when 'batch.created'
          handle_batch_created
        when 'batch.in_progress'
          handle_batch_in_progress
        when 'batch.completed'
          handle_batch_completed
        when 'batch.failed'
          handle_batch_failed
        when 'batch.cancelled'
          handle_batch_cancelled
        else
          log_info "Unhandled batch event type: #{event_type}"
        end
      end
      
      private
      
      def handle_batch_created
        batch_id = data['id']
        log_info "Batch created: #{batch_id}"
        
        # Track batch creation
        update_metadata('batch_id', batch_id)
        update_metadata('created_at', Time.current.iso8601)
      end
      
      def handle_batch_in_progress
        batch_id = data['id']
        log_info "Batch in progress: #{batch_id}"
        
        # Track progress
        update_metadata('started_at', Time.current.iso8601)
        update_metadata('status', 'in_progress')
      end
      
      def handle_batch_completed
        batch_id = data['id']
        request_counts = data['request_counts']
        
        log_info "Batch completed: #{batch_id}"
        log_info "Request counts: #{request_counts}"
        
        # Update metadata
        update_metadata('completed_at', Time.current.iso8601)
        update_metadata('request_counts', request_counts)
        update_metadata('status', 'completed')
        
        # Process batch results if needed
        process_batch_results(batch_id) if should_process_results?
        
        # Send notification
        notify_batch_completed(batch_id, request_counts)
      end
      
      def handle_batch_failed
        batch_id = data['id']
        errors = data['errors']
        
        log_error "Batch failed: #{batch_id}"
        log_error "Errors: #{errors}"
        
        # Update metadata
        update_metadata('failed_at', Time.current.iso8601)
        update_metadata('errors', errors)
        update_metadata('status', 'failed')
        
        # Handle failure recovery
        handle_batch_failure_recovery(batch_id, errors)
        
        # Send notification
        notify_batch_failed(batch_id, errors)
      end
      
      def handle_batch_cancelled
        batch_id = data['id']
        log_info "Batch cancelled: #{batch_id}"
        
        # Update metadata
        update_metadata('cancelled_at', Time.current.iso8601)
        update_metadata('status', 'cancelled')
        
        # Send notification
        notify_batch_cancelled(batch_id)
      end
      
      def should_process_results?
        # Determine if we should automatically process batch results
        # This could be based on configuration or batch metadata
        true
      end
      
      def process_batch_results(batch_id)
        log_info "Processing results for batch #{batch_id}"
        
        # Queue a job to download and process batch results
        if defined?(::BatchResultsProcessorJob)
          ::BatchResultsProcessorJob.perform_later(batch_id)
        end
      end
      
      def handle_batch_failure_recovery(batch_id, errors)
        # Determine if we should retry failed items
        if errors['failed_items'].present? && should_retry_failed_items?
          log_info "Scheduling retry for failed items in batch #{batch_id}"
          
          # Queue retry job if available
          if defined?(::BatchRetryJob)
            ::BatchRetryJob.perform_later(batch_id, errors['failed_items'])
          end
        end
      end
      
      def should_retry_failed_items?
        # Check configuration or metadata to determine retry policy
        webhook_event.metadata['retry_failed_items'] != false
      end
      
      # Notification methods
      
      def notify_batch_completed(batch_id, request_counts)
        total = request_counts['total'] || 0
        succeeded = request_counts['succeeded'] || 0
        failed = request_counts['failed'] || 0
        
        log_info "NOTIFICATION: Batch #{batch_id} completed - Total: #{total}, Succeeded: #{succeeded}, Failed: #{failed}"
      end
      
      def notify_batch_failed(batch_id, errors)
        log_error "NOTIFICATION: Batch #{batch_id} failed with errors: #{errors}"
      end
      
      def notify_batch_cancelled(batch_id)
        log_info "NOTIFICATION: Batch #{batch_id} was cancelled"
      end
    end
  end
end