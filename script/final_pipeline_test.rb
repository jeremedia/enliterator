#!/usr/bin/env ruby

# Final test to verify the pipeline works end-to-end

puts "=== FINAL PIPELINE TEST ==="
puts
puts "Starting a complete pipeline run to verify all fixes..."
puts

ekn = Ekn.find_by(name: "Meta-Enliterator")
batch = ekn.ingest_batches.last

puts "Using:"
puts "  EKN: #{ekn.name} (ID: #{ekn.id})"
puts "  Batch: #{batch.name} (ID: #{batch.id})"
puts "  Items: #{batch.ingest_items.count}"
puts

# Create a fresh pipeline run
pipeline_run = EknPipelineRun.create!(
  ekn: ekn,
  ingest_batch: batch,
  status: "initialized"
)

puts "Created pipeline run ##{pipeline_run.id}"
puts

# Start the pipeline
begin
  pipeline_run.start!
  puts "✅ Pipeline started successfully!"
  
  # Wait and check status
  5.times do |i|
    sleep 2
    pipeline_run.reload
    
    puts "\nStatus check #{i+1}:"
    puts "  Status: #{pipeline_run.status}"
    puts "  Stage: #{pipeline_run.current_stage}"
    puts "  Stage number: #{pipeline_run.current_stage_number}"
    
    if pipeline_run.error_message.present?
      puts "  ❌ Error: #{pipeline_run.error_message}"
      break
    end
    
    if pipeline_run.status == "completed"
      puts "  ✅ Pipeline completed!"
      break
    end
    
    if pipeline_run.status == "failed"
      puts "  ❌ Pipeline failed at stage: #{pipeline_run.failed_stage}"
      break
    end
  end
  
  # Final statistics
  puts "\n=== FINAL RESULTS ==="
  puts "Pipeline run ##{pipeline_run.id}"
  puts "Status: #{pipeline_run.status}"
  puts "Current stage: #{pipeline_run.current_stage}"
  
  items_with_rights = batch.ingest_items.where.not(provenance_and_rights_id: nil).count
  training_eligible = batch.ingest_items.where(training_eligible: true).count
  publishable = batch.ingest_items.where(publishable: true).count
  
  puts "\nItems processed:"
  puts "  With rights: #{items_with_rights}/#{batch.ingest_items.count}"
  puts "  Training eligible: #{training_eligible}"
  puts "  Publishable: #{publishable}"
  
  if items_with_rights > 0
    puts "\n✅ SUCCESS: Rights stage is processing items correctly!"
  else
    puts "\n⚠️ WARNING: No items have rights attached yet. Pipeline may still be running."
  end
  
rescue => e
  puts "❌ Error starting pipeline: #{e.message}"
  puts e.backtrace.first(5).join("\n")
end