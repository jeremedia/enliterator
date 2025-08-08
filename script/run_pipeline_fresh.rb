#!/usr/bin/env ruby

# Run a fresh pipeline from the beginning

batch = IngestBatch.last
ekn = batch.ekn

puts "Starting fresh pipeline for:"
puts "  EKN: #{ekn.name} (ID: #{ekn.id})"
puts "  Batch: #{batch.name} (ID: #{batch.id})"
puts "  Items: #{batch.ingest_items.count}"
puts

# Reset all items to initial state
puts "Resetting all items..."
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

# Clear any existing pipeline runs for this batch
puts "Clearing existing pipeline runs..."
EknPipelineRun.where(ingest_batch_id: batch.id).destroy_all

# Clear failed Solid Queue jobs
puts "Clearing failed jobs..."
SolidQueue::FailedExecution.destroy_all

# Use the orchestrator to start the pipeline
puts "Starting pipeline using Orchestrator..."
orchestrator = Pipeline::Orchestrator.new

begin
  # Run just the rights stage for testing
  pipeline_run = orchestrator.run_single_stage(batch: batch, stage: 'rights')
  
  puts "✅ Pipeline run ##{pipeline_run.id} started"
  puts "   Status: #{pipeline_run.status}"
  puts "   Current stage: #{pipeline_run.current_stage}"
  
  # Wait a moment for processing
  sleep 2
  
  # Check results
  pipeline_run.reload
  puts
  puts "=== Results after 2 seconds ==="
  puts "Pipeline status: #{pipeline_run.status}"
  puts "Current stage: #{pipeline_run.current_stage}"
  
  if pipeline_run.error_message.present?
    puts "Error: #{pipeline_run.error_message}"
  end
  
  # Check item results
  items_with_rights = batch.ingest_items.where.not(provenance_and_rights_id: nil).count
  training_eligible = batch.ingest_items.where(training_eligible: true).count
  publishable = batch.ingest_items.where(publishable: true).count
  completed = batch.ingest_items.where(triage_status: 'completed').count
  quarantined = batch.ingest_items.where(triage_status: 'quarantined').count
  failed = batch.ingest_items.where(triage_status: 'failed').count
  
  puts
  puts "Item statistics:"
  puts "  Items with rights: #{items_with_rights}"
  puts "  Training eligible: #{training_eligible}"
  puts "  Publishable: #{publishable}"
  puts "  Triage completed: #{completed}"
  puts "  Quarantined: #{quarantined}"
  puts "  Failed: #{failed}"
  
  if failed > 0
    puts
    puts "Failed items (first 3):"
    batch.ingest_items.where(triage_status: 'failed').limit(3).each do |item|
      puts "  #{File.basename(item.file_path)}: #{item.triage_error}"
    end
  end
  
rescue => e
  puts "❌ Error: #{e.message}"
  puts e.backtrace.first(5).join("\n")
end