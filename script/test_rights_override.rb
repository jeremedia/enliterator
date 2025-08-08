#!/usr/bin/env ruby
# Test script for rights inference override

puts "Testing Rights Inference Override for test data..."
puts "="*50

# Check environment variable
puts "RESPECT_TEST_RIGHTS_OVERRIDE: #{ENV['RESPECT_TEST_RIGHTS_OVERRIDE'] || 'true'}"
puts ""

# Create a test batch and item
b = IngestBatch.create!(
  name: "test_batch",
  source_type: "micro_test",
  ekn_id: Ekn.first&.id || 1
)

i = b.ingest_items.create!(
  file_path: "/tmp/test.txt",
  media_type: "text"
)

# Test inference
result = Rights::InferenceService.new(i).infer

puts "Results for micro_test item:"
puts "  Confidence: #{result[:confidence]}"
puts "  License: #{result[:license]}"
puts "  Publishable: #{result[:publishable]}"
puts "  Trainable: #{result[:trainable]}"
puts "  Method: #{result[:method]}"
puts "  Signals: #{result[:signals]}"

# Test with non-test item for comparison
b2 = IngestBatch.create!(
  name: "regular_batch",
  source_type: "upload",
  ekn_id: Ekn.first&.id || 1
)

i2 = b2.ingest_items.create!(
  file_path: "/tmp/regular.txt",
  media_type: "text"
)

result2 = Rights::InferenceService.new(i2).infer

puts "\nResults for regular item (for comparison):"
puts "  Confidence: #{result2[:confidence]}"
puts "  License: #{result2[:license]}"
puts "  Publishable: #{result2[:publishable]}"
puts "  Trainable: #{result2[:trainable]}"

# Cleanup
b.destroy
b2.destroy

puts "\n✅ Test complete!"