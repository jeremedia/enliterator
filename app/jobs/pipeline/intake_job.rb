# frozen_string_literal: true

# PURPOSE: Stage 1 of the 9-stage pipeline - Intake and Discovery
# This job processes raw file paths from an IngestBatch, reads their content,
# calculates hashes for deduplication, and prepares items for rights triage.
# CRITICAL: Must populate content and content_sample fields for downstream stages.
#
# Inputs: IngestBatch with file_paths
# Outputs: IngestItems with content, hashes, and media types ready for Stage 2

module Pipeline
  # Stage 1: Intake - Process IngestItems and prepare for rights triage
  class IntakeJob < BaseJob
    queue_as :intake
    
    def perform(pipeline_run_id)
      # BaseJob sets up @pipeline_run, @batch, @ekn via around_perform
      # Do NOT call super - BaseJob uses around_perform to wrap this method
      
      log_progress "Processing intake for #{@batch.ingest_items.count} items"
      
      processed = 0
      failed = 0
      
      @batch.ingest_items.find_each do |item|
        begin
          process_item(item)
          processed += 1
          
          # Log progress every 10 items
          if processed % 10 == 0
            log_progress "Processed #{processed} IngestItems for intake (file discovery)...", level: :debug
          end
        rescue => e
          log_progress "Failed to process item #{item.id}: #{e.message}", level: :warn
          failed += 1
          item.update!(triage_status: 'failed', triage_error: e.message)
        end
      end
      
      log_progress "✅ Intake complete: #{processed} processed, #{failed} failed"
      
      # Track metrics
      track_metric :items_processed, processed
      track_metric :items_failed, failed
      track_metric :total_items, @batch.ingest_items.count
      
      # Update batch status
      @batch.update!(status: 'intake_completed')
    end
    
    private
    
    def process_item(item)
      # Calculate file hash if not set
      if item.file_hash.blank? && File.exist?(item.file_path)
        item.file_hash = calculate_file_hash(item.file_path)
      end
      
      # Get file size
      if File.exist?(item.file_path)
        item.size_bytes = File.size(item.file_path)
      end
      
      # Use the new TriageService for content extraction and media type detection
      triage_result = Ingest::TriageService.new(item).call
      
      if triage_result[:success]
        log_progress "Item #{item.id}: #{File.basename(item.file_path)} triaged via #{triage_result[:extraction_method]}", level: :debug
      else
        log_progress "Triage failed for item #{item.id}: #{triage_result[:error]}", level: :warn
        item.update!(triage_status: 'failed', triage_error: triage_result[:error])
      end
    end
    
    
    def calculate_file_hash(file_path)
      Digest::SHA256.file(file_path).hexdigest
    rescue => e
      log_progress "Could not calculate hash for #{file_path}: #{e.message}", level: :warn
      nil
    end
    
    def collect_stage_metrics
      {
        items_processed: @metrics[:items_processed] || 0,
        items_failed: @metrics[:items_failed] || 0,
        total_items: @metrics[:total_items] || 0,
        batch_id: @batch.id
      }
    end
  end
end