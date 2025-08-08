#!/usr/bin/env ruby

# Script to test a fresh pipeline run with our fixes

puts "=== Fresh Pipeline Test ==="
puts

# Get the latest batch
batch = IngestBatch.last
ekn = batch.ekn

puts "Testing with:"
puts "  EKN: #{ekn.name} (ID: #{ekn.id})"
puts "  Batch: #{batch.name} (ID: #{batch.id})"
puts "  Items: #{batch.ingest_items.count}"
puts

# Reset all items to initial state for testing
puts "Resetting all items to initial intake state..."
batch.ingest_items.update_all(
  triage_status: 'pending',
  provenance_and_rights_id: nil,
  training_eligible: nil,
  publishable: nil,
  quarantined: nil,
  quarantine_reason: nil,
  triage_error: nil,
  lexicon_status: 'pending',
  pool_status: 'pending',
  graph_status: nil,
  embedding_status: nil
)

# Clear any failed job executions for this batch
puts "Clearing any failed Solid Queue jobs..."
failed_jobs = SolidQueue::FailedExecution.all
if failed_jobs.any?
  puts "  Found #{failed_jobs.count} failed jobs, clearing..."
  failed_jobs.destroy_all
end

# Create a new pipeline run
puts "Creating new pipeline run..."
pipeline_run = EknPipelineRun.create!(
  ekn: ekn,
  ingest_batch: batch,
  status: 'running',
  current_stage: 'rights',
  current_stage_number: 2,
  stage_statuses: {
    'intake' => 'completed',
    'rights' => 'running'
  },
  started_at: Time.current
)

puts "Pipeline run ##{pipeline_run.id} created"
puts

# Run the Rights::TriageJob directly
puts "Running Rights::TriageJob..."
begin
  job = Rights::TriageJob.new
  job.perform(pipeline_run.id)
  puts "✅ Rights::TriageJob completed successfully!"
rescue => e
  puts "❌ Rights::TriageJob failed: #{e.message}"
  puts e.backtrace.first(5).join("\n")
end

puts
puts "=== Results ==="

# Check results
items_with_rights = batch.ingest_items.where.not(provenance_and_rights_id: nil).count
training_eligible = batch.ingest_items.where(training_eligible: true).count
publishable = batch.ingest_items.where(publishable: true).count
completed = batch.ingest_items.where(triage_status: 'completed').count
quarantined = batch.ingest_items.where(triage_status: 'quarantined').count
failed = batch.ingest_items.where(triage_status: 'failed').count

puts "Items with rights: #{items_with_rights}"
puts "Training eligible: #{training_eligible}"
puts "Publishable: #{publishable}"
puts "Triage completed: #{completed}"
puts "Quarantined: #{quarantined}"
puts "Failed: #{failed}"

if failed > 0
  puts
  puts "Sample failures:"
  batch.ingest_items.where(triage_status: 'failed').limit(3).each do |item|
    puts "  #{File.basename(item.file_path)}: #{item.triage_error}"
  end
end