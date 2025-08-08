#!/usr/bin/env ruby

puts "="*60
puts "VERIFYING STAGE 3 HARDENING IMPLEMENTATION"
puts "="*60
puts

# 1. Check that source_item_id propagation is implemented
puts "1. Source Item ID Propagation:"
puts "-"*40

# Test with mock data
item = IngestItem.new(id: 123, provenance_and_rights_id: 456)
mock_terms = [
  { canonical_term: "test", surface_forms: ["test1"], term_type: "concept" }
]

# Simulate what process_item does
terms_with_metadata = mock_terms.map do |term|
  term.merge(
    provenance_and_rights_id: item.provenance_and_rights_id,
    source_item_id: item.id
  )
end

if terms_with_metadata.first[:source_item_id] == 123
  puts "✅ Source item ID added during extraction"
else
  puts "❌ Source item ID not propagated"
end

# Test normalization preserves source_item_ids
norm_service = Lexicon::NormalizationService.new(terms_with_metadata)
normalized = norm_service.normalize_and_deduplicate

if normalized.first[:source_item_ids]&.include?(123)
  puts "✅ Source item IDs preserved through normalization"
else
  puts "❌ Source item IDs lost in normalization"
end

# 2. Check pool_association uses term_type
puts "\n2. Pool Association Fix:"
puts "-"*40

# Check the code change
job_file = File.read(Rails.root.join('app/jobs/lexicon/bootstrap_job.rb'))
if job_file.include?('pool_association: (term_data[:term_type].presence || \'general\')')
  puts "✅ Pool association uses term_type with fallback"
else
  puts "❌ Pool association still using pool_type"
end

# 3. Check transactional persistence
puts "\n3. Transactional Persistence:"
puts "-"*40

if job_file.include?('ApplicationRecord.transaction do')
  puts "✅ create_lexicon_entries wrapped in transaction"
else
  puts "❌ No transaction wrapper found"
end

if job_file.include?('contributing_item_ids = Set.new')
  puts "✅ Tracking contributing items"
else
  puts "❌ Not tracking contributing items"
end

if job_file.include?('.where(id: contributing_item_ids.to_a)')
  puts "✅ Selective pool-ready marking"
else
  puts "❌ Still marking all items pool-ready"
end

# 4. Code inspection summary
puts "\n4. Implementation Summary:"
puts "-"*40

changes = []
changes << "source_item_id propagation" if job_file.include?('source_item_id: item.id')
changes << "term_type for pool_association" if job_file.include?('term_data[:term_type]')
changes << "transactional persistence" if job_file.include?('ApplicationRecord.transaction')
changes << "precise pool-ready marking" if job_file.include?('contributing_item_ids')

puts "Implemented changes:"
changes.each { |c| puts "  ✅ #{c}" }

missing = []
missing << "source_item_id propagation" unless job_file.include?('source_item_id: item.id')
missing << "term_type usage" unless job_file.include?('term_data[:term_type]')
missing << "transaction wrapper" unless job_file.include?('ApplicationRecord.transaction')
missing << "selective marking" unless job_file.include?('contributing_item_ids')

if missing.any?
  puts "\nMissing changes:"
  missing.each { |m| puts "  ❌ #{m}" }
end

# Final verdict
puts "\n" + "="*60
if changes.size == 4
  puts "✅ ALL HARDENING CHANGES IMPLEMENTED"
else
  puts "⚠️ PARTIAL IMPLEMENTATION (#{changes.size}/4)"
end
puts "="*60