#!/usr/bin/env ruby

# Ensure our fixes are loaded
load Rails.root.join('script/fix_pipeline_errors.rb')

pr = EknPipelineRun.find(37)
puts "Pipeline ##{pr.id} - Current stage: #{pr.current_stage}"
puts "Status: #{pr.status}"
puts

if pr.failed? && pr.current_stage == 'graph'
  puts "Retrying Graph stage..."
  
  # Check if we have pool entities to load
  batch = pr.ingest_batch
  items_with_pools = batch.ingest_items.where(pool_status: 'extracted')
  puts "Items with pool entities: #{items_with_pools.count}"
  
  if items_with_pools.any?
    # Get a sample of entities
    sample_item = items_with_pools.first
    if sample_item.pool_metadata
      puts "Sample pool metadata: #{sample_item.pool_metadata}"
    end
  end
  
  puts
  puts "Queueing Graph::AssemblyJob..."
  
  # Reset status and queue job
  pr.update_column(:status, 'running')
  job = Graph::AssemblyJob.perform_later(pr.id)
  
  puts "✅ Job queued"
  puts
  puts "Monitor with:"
  puts "  rails runner 'pr = EknPipelineRun.find(37); puts pr.status'"
else
  puts "Pipeline is not in a failed graph stage"
end