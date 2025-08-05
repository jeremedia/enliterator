#!/usr/bin/env ruby
# frozen_string_literal: true

# Test script for Lexicon Bootstrap pipeline
# Usage: bundle exec rails runner script/test_lexicon_bootstrap.rb

require 'benchmark'

puts "=== Testing Lexicon Bootstrap Pipeline ==="
puts

# Check for OpenAI API key
unless ENV['OPENAI_API_KEY']
  puts "ERROR: OPENAI_API_KEY environment variable not set!"
  puts "Please set it in your .env file or export it in your shell"
  exit 1
end

# 1. Create test batch and items
puts "1. Creating test batch and items..."
batch = IngestBatch.create!(
  name: "Lexicon Test Batch #{Time.current.to_i}",
  source_type: "test_data",
  status: :triage_completed,
  metadata: { test: true }
)

# Add timestamp to make content unique for each test run
timestamp = Time.current.to_i

# Create test content with rich terminology
test_contents = [
  {
    content: <<~TEXT,
      The Temple of Transformation, also known as the Temple of Tears, is a large-scale 
      interactive art installation at Burning Man. The Temple serves as a sacred space 
      for grief, remembrance, and healing. Participants often write messages to lost 
      loved ones on the wooden structure. The Temple is not the same as the Man burn.
      [Test run: #{timestamp}]
    TEXT
    file_path: "test/temple_description_#{timestamp}.txt"
  },
  {
    content: <<~TEXT,
      Radical Inclusion is one of the Ten Principles of Burning Man. It embodies the 
      philosophy that anyone may be a part of Burning Man. We welcome and respect the 
      stranger. No prerequisites exist for participation in our community. This principle 
      should not be confused with Radical Self-Expression, which is a different principle.
      [Test run: #{timestamp}]
    TEXT
    file_path: "test/principles_#{timestamp}.txt"
  },
  {
    content: <<~TEXT,
      The Black Rock Desert, also called the playa, is located in northwestern Nevada.
      The alkaline dust, known as playa dust, is extremely fine and gets into everything.
      The harsh environment includes extreme temperatures, dust storms (whiteouts), and
      no natural shade. Playa foot is a common condition caused by the alkaline dust.
      [Test run: #{timestamp}]
    TEXT
    file_path: "test/environment_#{timestamp}.txt"
  }
]

# Create items with rights already triaged
test_contents.each_with_index do |item_data, index|
  rights = ProvenanceAndRights.create!(
    source_ids: ["test_item_#{timestamp}_#{index}"],
    collectors: ["Test Script"],
    collection_method: "automated_test",
    consent_status: :explicit_consent,
    license_type: :cc_by,
    publishability: true,
    training_eligibility: true,
    valid_time_start: Time.current
  )

  IngestItem.create!(
    ingest_batch: batch,
    source_hash: Digest::SHA256.hexdigest(item_data[:content]),
    file_path: item_data[:file_path],
    content: item_data[:content],
    source_type: "text",
    media_type: :text,
    triage_status: :completed,
    provenance_and_rights: rights,
    metadata: { test: true }
  )
end

puts "  Created batch #{batch.id} with #{batch.ingest_items.count} items"
puts

# 2. Run the lexicon bootstrap job
puts "2. Running Lexicon::BootstrapJob..."
time = Benchmark.measure do
  Lexicon::BootstrapJob.perform_now(batch.id)
end
puts "  Completed in #{time.real.round(2)} seconds"
puts

# 3. Check results
puts "3. Checking results..."
batch.reload

puts "  Batch status: #{batch.status}"
puts "  Batch metadata: #{batch.metadata.inspect}"
puts

# Check lexicon entries
lexicon_count = LexiconAndOntology.count
puts "  Total lexicon entries: #{lexicon_count}"
puts

# Show some extracted terms
puts "4. Sample extracted terms:"
LexiconAndOntology.order(created_at: :desc).limit(10).each do |entry|
  puts "  - #{entry.term} (#{entry.pool_association})"
  puts "    Definition: #{entry.definition}"
  puts "    Surface forms: #{entry.surface_forms.join(', ')}" if entry.surface_forms.any?
  puts "    Negative forms: #{entry.negative_surface_forms.join(', ')}" if entry.negative_surface_forms.any?
  puts
end

# 5. Test term normalization
puts "5. Testing term normalization..."
test_queries = ["temple", "Temple of Tears", "playa dust", "radical inclusion"]
test_queries.each do |query|
  normalized = LexiconAndOntology.normalize_term(query)
  if normalized
    puts "  '#{query}' → '#{normalized.term}'"
  else
    puts "  '#{query}' → (not found)"
  end
end
puts

# 6. Check for any errors
failed_items = batch.ingest_items.where(lexicon_status: 'failed')
if failed_items.any?
  puts "6. Failed items:"
  failed_items.each do |item|
    puts "  - #{item.file_path}: #{item.lexicon_metadata['error']}"
  end
else
  puts "6. No failed items ✓"
end

puts
puts "=== Test Complete ==="