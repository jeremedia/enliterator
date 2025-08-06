module EmbeddingServices
  class BatchMonitorJob < ApplicationJob
    queue_as :embeddings
    
    # Job to monitor OpenAI Batch API jobs and process results when complete
    
    def perform(batch_id, ingest_batch_id: nil)
      Rails.logger.info "Monitoring batch #{batch_id}"
      
      batch = OPENAI.batches.retrieve(batch_id)
      
      case batch.status
      when 'completed'
        process_completed_batch(batch, ingest_batch_id)
      when 'failed'
        handle_failed_batch(batch, ingest_batch_id)
      when 'expired'
        handle_expired_batch(batch, ingest_batch_id)
      when 'cancelled'
        Rails.logger.info "Batch #{batch_id} was cancelled"
      when 'in_progress', 'finalizing'
        # Still processing - reschedule check
        reschedule_check(batch_id, ingest_batch_id)
      when 'validating'
        # Just started - check again soon
        self.class.set(wait: 1.minute).perform_later(batch_id, ingest_batch_id: ingest_batch_id)
      else
        Rails.logger.warn "Unknown batch status: #{batch.status}"
      end
    end
    
    private
    
    def process_completed_batch(batch, ingest_batch_id)
      Rails.logger.info "Processing completed batch #{batch.id}"
      
      processor = BatchProcessor.new(ingest_batch_id: ingest_batch_id)
      results = processor.process_results(batch.id)
      
      Rails.logger.info "Batch #{batch.id} processing complete: #{results.inspect}"
      
      # Update ingest batch status if all embedding batches are complete
      if ingest_batch_id
        check_all_batches_complete(ingest_batch_id)
      end
      
      # Send notification or trigger next stage
      notify_batch_complete(batch.id, results)
    end
    
    def handle_failed_batch(batch, ingest_batch_id)
      Rails.logger.error "Batch #{batch.id} failed"
      
      # Attempt to process any partial results
      if batch.output_file_id
        processor = BatchProcessor.new(ingest_batch_id: ingest_batch_id)
        results = processor.process_results(batch.id)
        Rails.logger.info "Recovered #{results[:processed]} embeddings from failed batch"
      end
      
      # Queue fallback to synchronous processing for failed items
      if batch.error_file_id
        queue_synchronous_fallback(batch, ingest_batch_id)
      end
      
      notify_batch_failed(batch.id)
    end
    
    def handle_expired_batch(batch, ingest_batch_id)
      Rails.logger.warn "Batch #{batch.id} expired"
      
      # Process any completed results
      if batch.output_file_id
        processor = BatchProcessor.new(ingest_batch_id: ingest_batch_id)
        results = processor.process_results(batch.id)
        Rails.logger.info "Recovered #{results[:processed]} embeddings from expired batch"
      end
      
      # Queue remaining items for synchronous processing
      queue_synchronous_fallback(batch, ingest_batch_id)
      
      notify_batch_expired(batch.id)
    end
    
    def reschedule_check(batch_id, ingest_batch_id)
      # Check less frequently as time goes on
      wait_time = case Time.current.hour
                  when 0..6 then 30.minutes  # Night time - check less often
                  when 20..23 then 30.minutes
                  else 15.minutes             # Business hours - check more often
                  end
      
      Rails.logger.info "Batch #{batch_id} still processing, checking again in #{wait_time.inspect}"
      
      self.class.set(wait: wait_time).perform_later(batch_id, ingest_batch_id: ingest_batch_id)
    end
    
    def queue_synchronous_fallback(batch, ingest_batch_id)
      Rails.logger.info "Queueing synchronous fallback for batch #{batch.id}"
      
      # Download error file to identify failed requests
      if batch.error_file_id
        error_response = OPENAI.files.content(batch.error_file_id)
        error_lines = error_response.text.split("\n").map { |line| JSON.parse(line) unless line.empty? }.compact
        
        # Extract custom IDs of failed requests
        failed_ids = error_lines.map { |line| line['custom_id'] }
        
        # Queue synchronous job for these specific items
        SynchronousFallbackJob.perform_later(
          failed_ids: failed_ids,
          ingest_batch_id: ingest_batch_id
        )
      end
    end
    
    def check_all_batches_complete(ingest_batch_id)
      # Get all batch IDs for this ingest batch
      batch_ids = Rails.cache.read("ingest_batch:#{ingest_batch_id}:batch_ids") || []
      
      all_complete = batch_ids.all? do |batch_id|
        batch = OPENAI.batches.retrieve(batch_id) rescue nil
        batch && %w[completed failed expired cancelled].include?(batch.status)
      end
      
      if all_complete
        Rails.logger.info "All embedding batches complete for ingest batch #{ingest_batch_id}"
        
        # Update ingest batch status
        ingest_batch = IngestBatch.find_by(id: ingest_batch_id)
        if ingest_batch
          ingest_batch.update!(
            status: 'embeddings_complete',
            metadata: ingest_batch.metadata.merge(
              embeddings_completed_at: Time.current,
              embedding_batch_ids: batch_ids
            )
          )
        end
        
        # Trigger next stage
        trigger_next_stage(ingest_batch_id)
      end
    end
    
    def trigger_next_stage(ingest_batch_id)
      # Could trigger Stage 7: Literacy Scoring
      Rails.logger.info "Ready to proceed to Stage 7 for ingest batch #{ingest_batch_id}"
    end
    
    def notify_batch_complete(batch_id, results)
      # Could send email, Slack notification, etc.
      Rails.logger.info "Batch #{batch_id} complete notification: #{results.inspect}"
    end
    
    def notify_batch_failed(batch_id)
      Rails.logger.error "Batch #{batch_id} failed notification"
    end
    
    def notify_batch_expired(batch_id)
      Rails.logger.warn "Batch #{batch_id} expired notification"
    end
  end
end