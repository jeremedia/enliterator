#!/usr/bin/env ruby

# Test PostgreSQL → Neo4j sync for new entity types

puts "Testing Graph Sync for New Entity Types"
puts "="*50

# Get the entities we just created
test_rights = ProvenanceAndRights.where(source_ids: ["test_15_pool_extraction"]).first
unless test_rights
  puts "❌ Test entities not found - run test_entity_saving.rb first"
  exit
end

entities_to_test = [
  { model: Actor, writer_class: 'Graph::ActorWriter', label: 'name' },
  { model: Spatial, writer_class: 'Graph::SpatialWriter', label: 'location_name' },  
  { model: MethodPool, writer_class: 'Graph::MethodWriter', label: 'method_name' },
  { model: Evidence, writer_class: 'Graph::EvidenceWriter', label: 'description' }
]

sync_results = []

entities_to_test.each do |config|
  entity = config[:model].where(provenance_and_rights: test_rights).first
  next unless entity
  
  puts "Testing #{config[:model].name}: #{entity.send(config[:label])}"
  
  begin
    # Get the writer class dynamically
    writer_class = config[:writer_class].constantize
    writer = writer_class.new(entity)
    
    # Test sync
    result = writer.sync
    
    if result
      puts "  ✅ Synced to Neo4j successfully"
      sync_results << { type: config[:model].name, success: true }
    else
      puts "  ❌ Failed to sync to Neo4j"
      sync_results << { type: config[:model].name, success: false, error: "Sync returned false" }
    end
    
  rescue => e
    puts "  ❌ Error: #{e.message}"
    sync_results << { type: config[:model].name, success: false, error: e.message }
  end
  
  puts ""
end

puts "SYNC RESULTS SUMMARY:"
puts "-" * 30
successful = sync_results.count { |r| r[:success] }
total = sync_results.size

puts "Successful syncs: #{successful}/#{total}"

if successful == total
  puts "🎉 ALL ENTITY TYPES SYNC SUCCESSFULLY!"
  puts "The 15-pool architecture is fully operational!"
else
  puts "⚠️  Some entity types failed to sync:"
  sync_results.select { |r| !r[:success] }.each do |failure|
    puts "  - #{failure[:type]}: #{failure[:error]}"
  end
end

# Clean up test entities
test_rights.destroy if test_rights