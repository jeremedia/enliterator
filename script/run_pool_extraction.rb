#!/usr/bin/env ruby

puts '=== RUNNING STAGE 4 - POOL FILLING ==='
batch = IngestBatch.find(30)
run = EknPipelineRun.find(7)

puts "Batch: #{batch.name} (#{batch.status})"
puts "Pipeline stage: #{run.current_stage} (#{run.current_stage_number})"

# Check ready items
ready_items = batch.ingest_items.where(lexicon_status: 'extracted', pool_status: 'pending')
puts "Items ready for pool extraction: #{ready_items.count}"

puts "\n=== RUNNING POOL EXTRACTION JOB ==="
begin
  job = Pools::ExtractionJob.new
  result = job.perform(batch.id)
  puts "Pool extraction completed successfully!"
  
  # Check results
  completed_items = batch.ingest_items.where(pool_status: 'extracted')
  failed_items = batch.ingest_items.where(pool_status: 'failed')
  
  puts "\nResults:"
  puts "  Extracted: #{completed_items.count} items"
  puts "  Failed: #{failed_items.count} items"
  
  # Check created entities
  puts "\nEntity counts:"
  %w[Idea Manifest Experience Relational Evolutionary Practical Emanation].each do |pool|
    recent_count = pool.constantize.where('created_at >= ?', 5.minutes.ago).count
    puts "  #{pool}: #{recent_count} new entities"
  end
  
  if completed_items.any?
    run.update!(current_stage: 'graph', current_stage_number: 5)
    puts "\n✅ Advanced pipeline to Stage 5 (Graph Assembly)"
  end
  
rescue => e
  puts "ERROR in pool extraction: #{e.message}"
  puts e.backtrace.first(5).join("\n")
end