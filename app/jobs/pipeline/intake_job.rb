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
      # Determine media type if not set or still default
      if item.media_type.blank? || item.media_type == 'unknown'
        item.media_type = detect_media_type(item.file_path)
      end
      
      # Calculate file hash if not set
      if item.file_hash.blank? && File.exist?(item.file_path)
        item.file_hash = calculate_file_hash(item.file_path)
      end
      
      # Get file size and content
      if File.exist?(item.file_path)
        item.size_bytes = File.size(item.file_path)
        
        # Read file content for rights inference and lexicon extraction
        begin
          full_content = File.read(item.file_path, encoding: 'UTF-8', invalid: :replace, undef: :replace)
          item.content_sample = full_content[0..4999] # First 5000 chars for rights inference
          item.content = full_content # Store full content for processing
        rescue => e
          log_progress "Could not read content from #{item.file_path}: #{e.message}", level: :warn
          item.content_sample = ""
          item.content = ""
        end
      end
      
      # Mark as pending for rights triage
      item.triage_status = 'pending'
      item.save!
      
      log_progress "Item #{item.id}: #{File.basename(item.file_path)} ready for triage", level: :debug
    end
    
    def detect_media_type(file_path)
      # Use the same detection logic as Pipeline::Orchestrator
      extension = File.extname(file_path).downcase
      basename = File.basename(file_path).downcase
      
      # First check for specific config file patterns
      if basename.match?(/^(gemfile|rakefile|dockerfile|makefile|procfile|guardfile|capfile|brewfile)/)
        return 'config'
      elsif basename.match?(/\.(yml|yaml)$/) && basename.match?(/(config|settings|database|credentials|secrets)/)
        return 'config'
      elsif basename == 'package.json' || basename == 'composer.json' || basename == 'cargo.toml'
        return 'config'
      end
      
      # Then check by extension
      case extension
      # Source code files
      when '.rb', '.py', '.js', '.ts', '.jsx', '.tsx', '.java', '.go', '.rs', '.cpp', '.c', '.h', 
           '.php', '.swift', '.kt', '.scala', '.clj', '.ex', '.exs', '.erl', '.hs', '.ml', '.fs'
        'code'
      
      # Documentation and text files  
      when '.md', '.txt', '.rst', '.adoc', '.org', '.textile', '.rdoc', '.pod', '.man'
        'text'
      
      # Configuration files
      when '.yml', '.yaml', '.toml', '.ini', '.cfg', '.conf', '.properties', '.env'
        'config'
      
      # Data files
      when '.json', '.xml', '.csv', '.tsv', '.jsonl', '.ndjson'
        # Try to distinguish between config and data based on path/name
        if file_path.include?('/config/') || file_path.include?('/settings/') || 
           basename.match?(/config|settings|manifest/)
          'config'
        else
          'data'
        end
      
      # Document files
      when '.pdf', '.doc', '.docx', '.odt', '.rtf', '.tex', '.epub'
        'document'
      
      # Image files
      when '.jpg', '.jpeg', '.png', '.gif', '.svg', '.ico', '.bmp', '.tiff', '.webp'
        'image'
      
      # Audio files
      when '.mp3', '.wav', '.ogg', '.m4a', '.flac', '.aac', '.wma'
        'audio'
      
      # Video files
      when '.mp4', '.mov', '.avi', '.wmv', '.flv', '.mkv', '.webm', '.m4v', '.mpg', '.mpeg'
        'video'
      
      # Binary files
      when '.exe', '.dll', '.so', '.dylib', '.bin', '.dat', '.db', '.sqlite', '.zip', '.tar', '.gz', '.rar'
        'binary'
      
      else
        'unknown'
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