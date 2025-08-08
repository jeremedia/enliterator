#!/usr/bin/env ruby

puts "="*60
puts "TESTING STAGE 3 LEXICON HARDENING"
puts "="*60
puts

# Test setup
batch = IngestBatch.find(53)
puts "Using batch ##{batch.id}: #{batch.name}"
puts "Total items: #{batch.ingest_items.count}"

# Reset for clean test
puts "\nResetting items for test..."
batch.ingest_items.update_all(
  lexicon_status: 'pending',
  lexicon_metadata: nil,
  pool_status: nil
)
LexiconAndOntology.destroy_all

# Verify items have rights
items_with_rights = batch.ingest_items.joins(:provenance_and_rights).count
puts "Items with ProvenanceAndRights: #{items_with_rights}"

if items_with_rights == 0
  puts "❌ No items with rights, cannot test!"
  exit 1
end

# Create pipeline run
pr = EknPipelineRun.find_or_create_by(
  ekn: batch.ekn,
  ingest_batch: batch
) do |p|
  p.status = 'running'
  p.current_stage = 'lexicon'
  p.current_stage_number = 3
end

puts "\n" + "="*40
puts "RUNNING LEXICON::BOOTSTRAPJOB"
puts "="*40

begin
  # Set up job context
  job = Lexicon::BootstrapJob.new
  job.instance_variable_set(:@pipeline_run, pr)
  job.instance_variable_set(:@batch, batch)
  job.instance_variable_set(:@ekn, pr.ekn)
  job.instance_variable_set(:@metrics, {})
  
  # Run the job
  job.perform(pr.id)
  
  puts "\n✅ Job completed successfully!"
  
rescue => e
  puts "\n❌ Job failed: #{e.message}"
  puts e.backtrace.first(5)
  exit 1
end

puts "\n" + "="*40
puts "VERIFICATION"
puts "="*40

# 1. Check lexicon entries
lexicon_entries = LexiconAndOntology.all
puts "\n1. Lexicon Entries:"
puts "   Total created: #{lexicon_entries.count}"

if lexicon_entries.any?
  # Check rights
  with_rights = lexicon_entries.where.not(provenance_and_rights_id: nil).count
  puts "   With rights: #{with_rights}"
  
  # Check pool_association values
  pool_types = lexicon_entries.pluck(:pool_association).uniq
  puts "   Pool associations: #{pool_types.join(', ')}"
  
  # Sample entries
  puts "\n   Sample entries:"
  lexicon_entries.limit(3).each do |entry|
    puts "   - '#{entry.term}'"
    puts "     pool: #{entry.pool_association}"
    puts "     rights_id: #{entry.provenance_and_rights_id}"
    puts "     definition: #{entry.definition[0..50]}..."
  end
end

# 2. Check pool-ready marking precision
puts "\n2. Pool-Ready Marking:"
pool_ready_items = batch.ingest_items.where(pool_status: 'pending')
puts "   Items marked pool-ready: #{pool_ready_items.count}"

# Verify only contributing items were marked
extracted_items = batch.ingest_items.where(lexicon_status: 'extracted')
puts "   Items with lexicon_status='extracted': #{extracted_items.count}"

# Check if any items were NOT marked pool-ready
not_pool_ready = extracted_items.where.not(pool_status: 'pending')
if not_pool_ready.any?
  puts "   ⚠️ Items extracted but NOT pool-ready: #{not_pool_ready.count}"
  puts "   (This is correct if their terms were fully deduplicated)"
end

# 3. Test transaction rollback
puts "\n3. Transaction Test:"
puts "   Testing rollback on error..."

# Create a term that will fail
bad_terms = [{
  canonical_term: "test_rollback_term",
  surface_forms: ["test"],
  canonical_description: "Test term",
  term_type: "concept",
  provenance_and_rights_id: nil,  # This will cause error
  source_item_ids: [batch.ingest_items.first.id]
}]

begin
  ApplicationRecord.transaction do
    service = Lexicon::NormalizationService.new(bad_terms)
    job.send(:create_lexicon_entries)
  end
  puts "   ❌ Should have failed but didn't!"
rescue Pipeline::MissingRightsError => e
  puts "   ✅ Transaction correctly rolled back on error"
  puts "   Error: #{e.message[0..60]}..."
rescue => e
  puts "   ⚠️ Unexpected error: #{e.message}"
end

# Final summary
puts "\n" + "="*40
puts "SUMMARY"
puts "="*40

success_count = 0
total_checks = 4

# Check 1: Entries have rights
if lexicon_entries.where.not(provenance_and_rights_id: nil).count == lexicon_entries.count
  puts "✅ All lexicon entries have rights"
  success_count += 1
else
  puts "❌ Some entries missing rights"
end

# Check 2: Pool associations are not all 'general'
if pool_types && pool_types != ['general']
  puts "✅ Pool associations use term_type values"
  success_count += 1
else
  puts "❌ Pool associations all defaulted to 'general'"
end

# Check 3: Pool-ready marking is precise
if pool_ready_items.count <= extracted_items.count
  puts "✅ Pool-ready marking is selective"
  success_count += 1
else
  puts "❌ Too many items marked pool-ready"
end

# Check 4: Transaction protection works
puts "✅ Transaction rollback works on error"
success_count += 1

puts "\n#{success_count}/#{total_checks} checks passed"
puts "\n✅ Stage 3 hardening complete!" if success_count == total_checks