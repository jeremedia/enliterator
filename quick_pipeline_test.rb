#!/usr/bin/env ruby

# Quick test of the fixed 15-pool pipeline

puts "TESTING FIXED 15-POOL PIPELINE"
puts "="*50

# Test content with entities that should trigger all major pool types
test_content = <<~CONTENT
  Senator Murkowski welcomed participants to Anchorage, Alaska. 
  Dr. Sarah Johnson from Arctic Research Institute presented statistical analysis methodology 
  using temperature measurements from weather stations. Safety protocols required 
  environmental assessments before drilling operations.
CONTENT

# Step 1: Extract entities
service = Pools::EntityExtractionService.new(
  content: test_content,
  lexicon_context: [],
  source_metadata: { test: true }
)

result = service.call
puts "✅ Extracted #{result[:entities].size} entities"

# Step 2: Save entities 
batch = IngestBatch.joins(:ekn).where(ekns: { slug: "arctic-research" }).first
rights = ProvenanceAndRights.create!(
  source_ids: ["quick_test_#{Time.current.to_i}"],
  collection_method: "test",
  consent_status: "implicit_consent", 
  license_type: "custom",
  valid_time_start: Time.current,
  publishability: true,
  training_eligibility: true
)

extraction_job = Pools::ExtractionJob.new
extraction_job.instance_variable_set(:@batch, batch)

saved_count = 0
result[:entities].each do |entity_data|
  begin
    converted_data = {
      pool: entity_data[:pool_type].split('_').map(&:capitalize).join,
      name: entity_data.dig(:attributes, :label),
      context: "Test context",
      confidence: entity_data[:confidence]
    }
    
    extraction_job.send(:save_entity, converted_data, rights)
    saved_count += 1
    puts "✅ Saved: #{converted_data[:pool]}"
  rescue => e
    puts "❌ Failed: #{entity_data[:pool_type]} - #{e.message}"
  end
end

puts "\nRESULTS:"
puts "Extracted: #{result[:entities].size} entities"
puts "Saved: #{saved_count} entities" 
puts "Success rate: #{(saved_count.to_f / result[:entities].size * 100).round(1)}%"

# Check what we actually saved
puts "\nSAVED ENTITIES:"
puts "Actors: #{Actor.where(provenance_and_rights: rights).count}"
puts "Spatials: #{Spatial.where(provenance_and_rights: rights).count}"
puts "Methods: #{MethodPool.where(provenance_and_rights: rights).count}"
puts "Evidence: #{Evidence.where(provenance_and_rights: rights).count}"
puts "Risks: #{Risk.where(provenance_and_rights: rights).count}"

# Cleanup
rights.destroy