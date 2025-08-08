#!/usr/bin/env ruby

# Test the rights inference logic with our fixes

puts "=== TESTING RIGHTS INFERENCE LOGIC ==="
puts

batch = IngestBatch.last
test_item = batch.ingest_items.first

puts "Testing with: #{File.basename(test_item.file_path)}"
puts "  Path: #{test_item.file_path}"
puts "  Media type: #{test_item.media_type}"
puts

# Test the inference
service = Rights::InferenceService.new(test_item)
result = service.infer

puts "Inference Results:"
puts "  License: #{result[:license]}"
puts "  Consent: #{result[:consent]}"
puts "  Confidence: #{result[:confidence]}"
puts "  Publishable: #{result[:publishable]}"
puts "  Trainable: #{result[:trainable]}"
puts "  Source type: #{result[:source_type]}"
puts

# Now test what ProvenanceAndRights would derive
puts "Testing ProvenanceAndRights derivation:"

# Map the consent status
consent_status = case result[:consent].to_s.downcase
when 'explicit', 'yes', 'granted', 'explicit_consent'
  'explicit_consent'
when 'implicit', 'assumed', 'implicit_consent'
  'implicit_consent'  
when 'no', 'denied', 'refused', 'no_consent'
  'no_consent'
when 'withdrawn', 'revoked'
  'withdrawn'
else
  result[:confidence].to_f >= 0.8 ? 'implicit_consent' : 'unknown'
end

# Map the license type
license_type = if result[:license] == 'cc_by'
  'cc_by'
elsif result[:license] == 'unspecified'
  'unspecified'
else
  'cc_by'  # Default for our code
end

puts "  Mapped consent_status: #{consent_status}"
puts "  Mapped license_type: #{license_type}"

# Create a temporary ProvenanceAndRights to test derivation
pr = ProvenanceAndRights.new(
  source_ids: ['test'],
  collection_method: 'test',
  consent_status: consent_status,
  license_type: license_type,
  valid_time_start: Time.current,
  quarantined: false
)

# Trigger the derive_rights callback
pr.valid?

puts
puts "ProvenanceAndRights would derive:"
puts "  Publishability: #{pr.publishability}"
puts "  Training eligibility: #{pr.training_eligibility}"

if pr.publishability && pr.training_eligibility
  puts
  puts "✅ SUCCESS: Item would be both publishable and trainable!"
else
  puts
  puts "❌ PROBLEM: Item would not be fully usable"
  puts "  Check the license_type (#{license_type}) and consent_status (#{consent_status})"
end