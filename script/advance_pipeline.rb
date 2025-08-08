#!/usr/bin/env ruby

pr = EknPipelineRun.find(37)
batch = pr.ingest_batch

puts "Pipeline ##{pr.id} - Current: #{pr.current_stage} (#{pr.status})"

# Check completion
completed = batch.ingest_items.where(lexicon_status: "extracted").count
total = batch.ingest_items.count
puts "Lexicon extraction: #{completed}/#{total} completed"

if completed == total
  puts "\n✅ Stage 3 complete, advancing to Stage 4..."
  
  # Fix status if failed
  if pr.status == "failed"
    pr.update_column(:status, "running")
    puts "Fixed status: failed → running"
  end
  
  # Advance to Stage 4
  pr.update!(
    current_stage: "pools",
    current_stage_number: 4
  )
  
  # Queue the Pools job
  job = Pools::ExtractionJob.perform_later(pr.id)
  puts "Advanced to Stage 4 (Pools)"
  puts "Queued Pools::ExtractionJob"
  
  # Monitor
  puts "\nPipeline now at: #{pr.reload.current_stage}"
else
  puts "❌ Cannot advance - not all items processed"
end