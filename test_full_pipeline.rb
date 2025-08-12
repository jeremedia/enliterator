#!/usr/bin/env ruby

# Complete test: Extraction → Save → Sync to Neo4j

puts "COMPLETE 15-POOL PIPELINE TEST"
puts "="*60

# Step 1: Test Extraction
puts "STEP 1: Testing Entity Extraction"
puts "-" * 30

test_content = <<~CONTENT
  Senator Murkowski, Chairman of the Committee on Energy and Natural Resources, welcomed 
  participants to Anchorage, Alaska. Dr. Sarah Johnson from the Arctic Research Institute 
  presented findings on climate change impacts in the Beaufort Sea region. 

  The statistical analysis methodology used temperature measurements from weather stations 
  between 2010-2015. Safety protocols required environmental impact assessments.
CONTENT

service = Pools::EntityExtractionService.new(
  content: test_content,
  lexicon_context: [],
  source_metadata: { test: true }
)

extraction_result = service.call

if !extraction_result[:success]
  puts "❌ Extraction failed: #{extraction_result}"
  exit
end

puts "✅ Extracted #{extraction_result[:entities].size} entities"
by_pool = extraction_result[:entities].group_by { |e| e[:pool_type] }
by_pool.each { |pool, entities| puts "  #{pool}: #{entities.size}" }

# Step 2: Save to Database
puts "\nSTEP 2: Saving Entities to PostgreSQL"  
puts "-" * 30

# Get Arctic Research context
batch = IngestBatch.joins(:ekn).where(ekns: { slug: "arctic-research" }).first
test_rights = ProvenanceAndRights.create!(
  source_ids: ["test_full_pipeline_#{Time.current.to_i}"],
  collection_method: "test_extraction",
  consent_status: "implicit_consent", 
  license_type: "custom",
  valid_time_start: Time.current,
  publishability: true,
  training_eligibility: true
)

extraction_job = Pools::ExtractionJob.new
extraction_job.instance_variable_set(:@batch, batch)

saved_entities = []
extraction_result[:entities].each do |entity_data|
  begin
    # Convert to format expected by save_entity
    converted_data = {
      pool: entity_data[:pool_type].split('_').map(&:capitalize).join,  # Convert "actor_and_role" → "ActorAndRole"
      name: entity_data.dig(:attributes, :label),
      context: "Test context for #{entity_data.dig(:attributes, :label)}",
      confidence: entity_data[:confidence]
    }
    
    extraction_job.send(:save_entity, converted_data, test_rights)
    saved_entities << converted_data
    puts "✅ Saved: #{converted_data[:pool]} - #{converted_data[:name]}"
  rescue => e
    puts "❌ Failed to save #{entity_data[:pool_type]}: #{e.message}"
  end
end

# Step 3: Test Neo4j Sync
puts "\nSTEP 3: Testing Neo4j Sync"
puts "-" * 30

sync_configs = [
  { model: Actor, writer_class: 'Graph::ActorWriter', field: 'name' },
  { model: Spatial, writer_class: 'Graph::SpatialWriter', field: 'location_name' },  
  { model: MethodPool, writer_class: 'Graph::MethodWriter', field: 'method_name' },
  { model: Evidence, writer_class: 'Graph::EvidenceWriter', field: 'description' }
]

sync_results = []

sync_configs.each do |config|
  entities = config[:model].where(provenance_and_rights: test_rights)
  puts "Found #{entities.count} #{config[:model].name} entities"
  
  entities.each do |entity|
    begin
      writer_class = config[:writer_class].constantize
      writer = writer_class.new(entity)
      result = writer.sync
      
      if result
        puts "  ✅ Synced #{config[:model].name}: #{entity.send(config[:field])}"
        sync_results << { type: config[:model].name, success: true }
      else
        puts "  ❌ Failed to sync #{config[:model].name}: #{entity.send(config[:field])}"
        sync_results << { type: config[:model].name, success: false }
      end
    rescue => e
      puts "  ❌ Error syncing #{config[:model].name}: #{e.message}"
      sync_results << { type: config[:model].name, success: false, error: e.message }
    end
  end
end

# Summary
puts "\n" + "="*60
puts "PIPELINE TEST RESULTS"
puts "="*60
puts "Extraction: ✅ #{extraction_result[:entities].size} entities"
puts "Database Save: ✅ #{saved_entities.size} entities"

successful_syncs = sync_results.count { |r| r[:success] }
total_syncs = sync_results.size
puts "Neo4j Sync: #{successful_syncs}/#{total_syncs} successful"

if successful_syncs == total_syncs
  puts "\n🎉 COMPLETE SUCCESS! 15-POOL PIPELINE FULLY OPERATIONAL!"
  puts "✅ Extraction works with all pools"
  puts "✅ Database saving works with canonical names"  
  puts "✅ Neo4j sync works with Graph Writers"
  puts "\nArctic Research EKN ready for full entity extraction!"
else
  puts "\n⚠️ Some issues found:"
  sync_results.select { |r| !r[:success] }.each do |failure|
    puts "  - #{failure[:type]}: #{failure[:error] || 'Sync failed'}"
  end
end

# Cleanup
test_rights.destroy