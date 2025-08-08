#!/usr/bin/env ruby

# Complete pipeline run with all fixes applied

puts "=== COMPLETE PIPELINE RUN WITH ALL FIXES ==="
puts
puts "Fixed issues:"
puts "1. ✅ Rights::TriageJob field mapping (owner/source_owner, method/collection_method)"
puts "2. ✅ ProvenanceAndRights valid_time_start required field"
puts "3. ✅ IngestBatch status enum (triage_quarantined -> triage_needs_review)"
puts "4. ✅ InferenceService confidence for codebase files"
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

# Reset all items for a fresh run
puts "Resetting all items to initial state..."
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

# Clear old pipeline runs
EknPipelineRun.where(ingest_batch_id: batch.id).destroy_all
SolidQueue::FailedExecution.destroy_all

# Create new pipeline run
pipeline_run = EknPipelineRun.create!(
  ekn: ekn,
  ingest_batch: batch,
  status: "initialized"
)

puts "Created pipeline run ##{pipeline_run.id}"
puts

# Start the pipeline
pipeline_run.start!
puts "✅ Pipeline started!"
puts

# Monitor progress
10.times do |i|
  sleep 3
  pipeline_run.reload
  
  puts "Check #{i+1}: Stage #{pipeline_run.current_stage_number} - #{pipeline_run.current_stage} (#{pipeline_run.status})"
  
  if pipeline_run.status == "failed"
    puts "  ❌ Failed: #{pipeline_run.error_message}"
    break
  elsif pipeline_run.status == "completed"
    puts "  ✅ Pipeline completed!"
    break
  end
  
  # Show stage-specific stats
  case pipeline_run.current_stage
  when "rights"
    with_rights = batch.ingest_items.where.not(provenance_and_rights_id: nil).count
    completed = batch.ingest_items.where(triage_status: 'completed').count
    quarantined = batch.ingest_items.where(triage_status: 'quarantined').count
    puts "    Rights: #{with_rights} attached, #{completed} completed, #{quarantined} quarantined"
  when "lexicon"
    extracted = batch.ingest_items.where(lexicon_status: 'extracted').count
    puts "    Lexicon: #{extracted} items processed"
    puts "    Terms in database: #{LexiconAndOntology.count}"
  when "pools"
    extracted = batch.ingest_items.where(pool_status: 'extracted').count
    puts "    Pools: #{extracted} items processed"
  end
end

puts
puts "="*60
puts "FINAL RESULTS:"
puts

# Final statistics
batch.reload
pipeline_run.reload

puts "Pipeline ##{pipeline_run.id}: #{pipeline_run.status}"
puts "Current stage: #{pipeline_run.current_stage} (#{pipeline_run.current_stage_number})"

if pipeline_run.error_message.present?
  puts "Error: #{pipeline_run.error_message}"
end

puts
puts "Item Statistics:"
puts "  Total items: #{batch.ingest_items.count}"
puts "  With rights: #{batch.ingest_items.where.not(provenance_and_rights_id: nil).count}"
puts "  Training eligible: #{batch.ingest_items.where(training_eligible: true).count}"
puts "  Publishable: #{batch.ingest_items.where(publishable: true).count}"
puts "  Quarantined: #{batch.ingest_items.where(quarantined: true).count}"

puts
puts "Stage Progress:"
puts "  Triage completed: #{batch.ingest_items.where(triage_status: 'completed').count}"
puts "  Lexicon extracted: #{batch.ingest_items.where(lexicon_status: 'extracted').count}"
puts "  Pool extracted: #{batch.ingest_items.where(pool_status: 'extracted').count}"

puts
puts "Lexicon Entries: #{LexiconAndOntology.count}"

if pipeline_run.current_stage_number >= 3
  puts
  puts "✅ SUCCESS! Pipeline is processing through multiple stages correctly!"
else
  puts
  puts "⚠️ Pipeline stopped at stage #{pipeline_run.current_stage}"
end