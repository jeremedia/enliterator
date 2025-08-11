#!/usr/bin/env ruby

# Fix missing provenance_and_rights for Arctic Research batch
batch = IngestBatch.find(9)

puts "🔧 FIXING ARCTIC RESEARCH RIGHTS"
puts "=" * 50

# Create batch-level rights for Arctic Research
rights = ProvenanceAndRights.create!(
  source_ids: ["arctic_research_batch_#{batch.id}"],
  collectors: ["MarkItDown Pipeline"],
  collection_method: "pdf_extraction",
  consent_status: :explicit_consent,
  license_type: :fair_use,
  publishability: true,
  training_eligibility: true,
  valid_time_start: Time.current
)

puts "✅ Created ProvenanceAndRights ##{rights.id}"

# Assign to all items
updated = batch.ingest_items.update_all(provenance_and_rights_id: rights.id)
puts "✅ Updated #{updated} items with rights_id #{rights.id}"

# Verify
with_rights = batch.ingest_items.where.not(provenance_and_rights_id: nil).count
total = batch.ingest_items.count
puts "✅ Items with rights: #{with_rights}/#{total}"

# Reset pipeline run for retry
pipeline_run = EknPipelineRun.find(3)
pipeline_run.update!(
  status: 'running',
  current_stage: 'lexicon_bootstrap',
  error_message: nil
)
puts "✅ Reset pipeline run #3 for retry"

puts "\n🎯 Ready to retry lexicon extraction!"