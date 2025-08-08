#!/usr/bin/env ruby

# Final pipeline run with all rights logic fixes

puts "=== FINAL PIPELINE RUN WITH CORRECTED RIGHTS LOGIC ==="
puts
puts "Fixed issues:"
puts "1. ✅ InferenceService now assigns 'cc_by' license for our codebase"
puts "2. ✅ InferenceService confidence = 0.9 for our code"
puts "3. ✅ Publishability = true for our code"
puts "4. ✅ Trainability = true for our code"
puts
puts "="*60
puts

ekn = Ekn.find_by(name: "Meta-Enliterator")
batch = ekn.ingest_batches.last

puts "Configuration:"
puts "  EKN: #{ekn.name} (ID: #{ekn.id})"
puts "  Batch: #{batch.name} (ID: #{batch.id})"
puts "  Items: #{batch.ingest_items.count}"
puts

# Reset items for fresh run
puts "Resetting items..."
batch.ingest_items.update_all(
  triage_status: 'pending',
  provenance_and_rights_id: nil,
  training_eligible: nil,
  publishable: nil,
  quarantined: nil,
  quarantine_reason: nil,
  triage_error: nil,
  lexicon_status: 'pending',
  pool_status: 'pending'
)

# Clear old runs
EknPipelineRun.where(ingest_batch_id: batch.id).destroy_all
SolidQueue::FailedExecution.destroy_all

# Create and start pipeline
pipeline_run = EknPipelineRun.create!(
  ekn: ekn,
  ingest_batch: batch,
  status: "initialized"
)

puts "Created pipeline run ##{pipeline_run.id}"
puts

pipeline_run.start!
puts "✅ Pipeline started!"
puts

# Quick monitoring - just check rights stage results
sleep 10  # Give it time to process through rights stage

pipeline_run.reload
batch.reload

puts "Pipeline Status: #{pipeline_run.status}"
puts "Current Stage: #{pipeline_run.current_stage} (#{pipeline_run.current_stage_number})"
puts

puts "="*60
puts "RIGHTS STAGE RESULTS:"
puts

total = batch.ingest_items.count
with_rights = batch.ingest_items.where.not(provenance_and_rights_id: nil).count
training = batch.ingest_items.where(training_eligible: true).count
publishable = batch.ingest_items.where(publishable: true).count
completed = batch.ingest_items.where(triage_status: 'completed').count
quarantined = batch.ingest_items.where(quarantined: true).count

puts "Items processed: #{with_rights}/#{total}"
puts "Training eligible: #{training}/#{total} (#{(training * 100.0 / total).round(1)}%)"
puts "Publishable: #{publishable}/#{total} (#{(publishable * 100.0 / total).round(1)}%)"
puts "Completed (not quarantined): #{completed}/#{total}"
puts "Quarantined: #{quarantined}/#{total}"

puts

if training > 250 && publishable > 250
  puts "🎉 SUCCESS! The vast majority of items are now trainable and publishable!"
  puts "This is correct for our own codebase being processed as Meta-Enliterator."
elsif training > 100
  puts "✅ Good progress! #{training} items are trainable."
  puts "Pipeline may still be processing..."
else
  puts "⚠️ Still seeing low numbers. Checking sample items..."
  
  batch.ingest_items.limit(3).each do |item|
    pr = item.provenance_and_rights
    puts
    puts "#{File.basename(item.file_path)}:"
    puts "  license: #{pr&.license_type || 'none'}"
    puts "  training: #{item.training_eligible}"
    puts "  publishable: #{item.publishable}"
  end
end