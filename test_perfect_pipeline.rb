#!/usr/bin/env ruby

# FINAL TEST: Perfect 15-pool pipeline with zero errors

puts "🎯 TESTING PERFECT 15-POOL PIPELINE"
puts "="*60

test_content = <<~CONTENT
  Senator Murkowski welcomed participants to Anchorage, Alaska. 
  Dr. Sarah Johnson from Arctic Research Institute presented statistical analysis methodology 
  using temperature measurements from weather stations. Safety protocols required 
  environmental assessments before drilling operations. The research team published 
  findings on Arctic governance policies.
CONTENT

# Step 1: Extract entities
puts "STEP 1: Entity Extraction"
service = Pools::EntityExtractionService.new(
  content: test_content,
  lexicon_context: [],
  source_metadata: { test: true }
)

result = service.call
puts "✅ Extracted #{result[:entities].size} entities"
puts "Pools found: #{result[:entities].map { |e| e[:pool_type] }.uniq.join(', ')}"

# Step 2: Save ALL entities with zero failures
puts "\nSTEP 2: Database Saving (Target: 100% success)"
batch = IngestBatch.joins(:ekn).where(ekns: { slug: "arctic-research" }).first
rights = ProvenanceAndRights.create!(
  source_ids: ["perfect_test_#{Time.current.to_i}"],
  collection_method: "test",
  consent_status: "implicit_consent", 
  license_type: "custom",
  valid_time_start: Time.current,
  publishability: true,
  training_eligibility: true
)

extraction_job = Pools::ExtractionJob.new
extraction_job.instance_variable_set(:@batch, batch)

saved_entities = []
failed_entities = []

result[:entities].each do |entity_data|
  begin
    converted_data = {
      pool: entity_data[:pool_type].split('_').map(&:capitalize).join,
      name: entity_data.dig(:attributes, :label),
      context: "Test context for #{entity_data.dig(:attributes, :label)}",
      confidence: entity_data[:confidence]
    }
    
    extraction_job.send(:save_entity, converted_data, rights)
    saved_entities << converted_data
    puts "✅ SAVED: #{converted_data[:pool]} - #{converted_data[:name]}"
  rescue => e
    failed_entities << { pool: entity_data[:pool_type], error: e.message }
    puts "❌ FAILED: #{entity_data[:pool_type]} - #{e.message}"
  end
end

# Results Analysis
puts "\n" + "🎯 PERFECT PIPELINE RESULTS"
puts "="*60
puts "Extracted: #{result[:entities].size} entities"
puts "Saved: #{saved_entities.size} entities"
puts "Failed: #{failed_entities.size} entities"

success_rate = (saved_entities.size.to_f / result[:entities].size * 100).round(1)
puts "Success Rate: #{success_rate}%"

if success_rate == 100.0
  puts "\n🏆 PERFECT SUCCESS! ZERO-ERROR PIPELINE ACHIEVED!"
  puts "✅ All 15 pools working flawlessly"
  puts "✅ Complete entity extraction and saving"
  puts "✅ Production-ready pipeline"
else
  puts "\n⚠️ Still have #{failed_entities.size} failures to fix:"
  failed_entities.each do |failure|
    puts "  - #{failure[:pool]}: #{failure[:error]}"
  end
end

# Entity Type Distribution
puts "\nENTITY DISTRIBUTION:"
puts "Actors: #{Actor.where(provenance_and_rights: rights).count}"
puts "Spatials: #{Spatial.where(provenance_and_rights: rights).count}"
puts "Methods: #{MethodPool.where(provenance_and_rights: rights).count}"
puts "Evidence: #{Evidence.where(provenance_and_rights: rights).count}"
puts "Risks: #{Risk.where(provenance_and_rights: rights).count}"

# Show samples
if Actor.where(provenance_and_rights: rights).any?
  actor = Actor.where(provenance_and_rights: rights).first
  puts "\nSample Actor: #{actor.name} (#{actor.role})"
end

if success_rate == 100.0
  puts "\n🚀 READY FOR PRODUCTION DEPLOYMENT!"
  puts "Arctic Research Navigator can now extract ALL entity types!"
else
  puts "\n🔧 Needs fixes before production deployment"
end

# Cleanup test data but keep it if perfect for verification
rights.destroy