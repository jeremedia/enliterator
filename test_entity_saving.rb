#!/usr/bin/env ruby

# Test entity saving with our updated save_entity method

# Get Arctic Research batch for proper rights context
batch = IngestBatch.joins(:ekn).where(ekns: { slug: "arctic-research" }).first
raise "Arctic Research batch not found" unless batch

# Create test rights record
test_rights = ProvenanceAndRights.create!(
  source_ids: ["test_15_pool_extraction"],
  collection_method: "test_extraction",
  consent_status: "implicit_consent",
  license_type: "custom", 
  valid_time_start: Time.current,
  publishability: true,
  training_eligibility: true
)

# Test entities with new canonical names (what our extraction now returns)
test_entities = [
  {
    pool: "ActorAndRole",
    name: "Dr. Sarah Johnson", 
    context: "researcher from Arctic Research Institute",
    confidence: 0.98
  },
  {
    pool: "Spatial",
    name: "Beaufort Sea region",
    context: "geographic area mentioned in climate change research", 
    confidence: 0.97
  },
  {
    pool: "MethodAndModel", 
    name: "Statistical analysis methodology",
    context: "analytical approach used for temperature data",
    confidence: 0.96
  },
  {
    pool: "EvidenceAndObservation",
    name: "Temperature measurements",
    context: "primary data from weather stations 2010-2015",
    confidence: 0.95
  }
]

puts "Testing Entity Saving with New Canonical Names"
puts "="*50

# Create extraction job instance to access save_entity method
extraction_job = Pools::ExtractionJob.new
extraction_job.instance_variable_set(:@batch, batch)

test_entities.each do |entity_data|
  puts "Testing: #{entity_data[:pool]} - #{entity_data[:name]}"
  
  begin
    # Call our updated save_entity method
    extraction_job.send(:save_entity, entity_data, test_rights)
    puts "  ✅ SAVED successfully"
  rescue => e
    puts "  ❌ FAILED: #{e.message}"
  end
end

puts ""
puts "Checking database records created:"

# Check what was actually created
puts "Actor records: #{Actor.where(provenance_and_rights: test_rights).count}"
puts "Spatial records: #{Spatial.where(provenance_and_rights: test_rights).count}"  
puts "MethodPool records: #{MethodPool.where(provenance_and_rights: test_rights).count}"
puts "Evidence records: #{Evidence.where(provenance_and_rights: test_rights).count}"

# Show some details
if Actor.where(provenance_and_rights: test_rights).any?
  actor = Actor.where(provenance_and_rights: test_rights).first
  puts "Sample Actor: #{actor.label} (#{actor.actor_type})"
end

# Clean up test data
test_rights.destroy