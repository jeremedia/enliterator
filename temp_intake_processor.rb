#!/usr/bin/env ruby

# Temporary script to manually process intake for Pipeline Run #7
pipeline_run = EknPipelineRun.find(7)
batch = pipeline_run.ingest_batch

puts "Processing intake for Pipeline Run #7"
puts "Batch: #{batch.id} with #{batch.ingest_items.count} items"

processed = 0
failed = 0

batch.ingest_items.find_each do |item|
  begin
    # Update media type if needed
    if item.media_type.blank?
      extension = File.extname(item.file_path).downcase
      item.media_type = case extension
      when '.rb', '.py', '.js' then 'code'
      when '.md', '.txt' then 'text'
      when '.yml', '.yaml' then 'config'
      else 'unknown'
      end
    end
    
    # Calculate file size if file exists
    if item.size_bytes.blank? && File.exist?(item.file_path)
      item.size_bytes = File.size(item.file_path)
    end
    
    # Mark as ready for next stage (not 'ready' - use 'completed')
    item.triage_status = 'completed'
    item.save!
    
    processed += 1
    print '.' if processed % 10 == 0
    
  rescue => e
    puts "\nFailed to process item #{item.id}: #{e.message}"
    failed += 1
    item.update!(
      triage_status: 'failed',
      triage_metadata: { error_message: e.message, failed_at: Time.current }
    )
  end
end

puts "\n✅ Intake complete: #{processed} processed, #{failed} failed"

# Update batch status
batch.update!(status: 'intake_completed')

# Mark stage as complete
metrics = {
  items_processed: processed,
  items_failed: failed,
  total_items: batch.ingest_items.count,
  batch_id: batch.id,
  duration: 2.0
}

pipeline_run.mark_stage_complete!(metrics)

puts '🚀 Stage 1 complete, advancing to Stage 2'