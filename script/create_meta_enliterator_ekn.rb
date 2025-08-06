#!/usr/bin/env ruby
# Create an isolated EKN for the Meta-Enliterator data (Enliterator analyzing itself)
# This takes the data from Batch #7 and creates a proper isolated Knowledge Navigator

require_relative '../config/environment'

puts "\n" + "="*80
puts "Creating Meta-Enliterator EKN"
puts "="*80

# Find the completed batch with Enliterator data
completed_batch = IngestBatch.find_by(id: 7, status: 'completed')

unless completed_batch
  puts "ERROR: Cannot find completed IngestBatch #7"
  puts "Available batches:"
  IngestBatch.pluck(:id, :name, :status).each do |id, name, status|
    puts "  #{id}: #{name} (#{status})"
  end
  exit 1
end

puts "\n1. Found source batch:"
puts "   Name: #{completed_batch.name}"
puts "   Status: #{completed_batch.status}"
puts "   Items: #{completed_batch.ingest_items.count}"
puts "   Literacy Score: #{completed_batch.literacy_score}"

# Create the new EKN with isolation
puts "\n2. Creating isolated Meta-Enliterator EKN..."
ekn = EknManager.create_ekn(
  name: "Meta-Enliterator",
  description: "Enliterator's understanding of itself - the codebase as a knowledge domain"
)

puts "   ✓ Created EKN ##{ekn.id}"
puts "   - Neo4j database: #{ekn.neo4j_database_name}"
puts "   - PostgreSQL schema: #{ekn.postgres_schema_name}"
puts "   - Storage path: #{ekn.storage_root_path}"

# Now we need to migrate the data from the default database to the isolated EKN database
puts "\n3. Migrating data to isolated database..."

# Update the IngestBatch to point to the new isolated resources
completed_batch.update!(
  id: ekn.id, # Use the EKN ID so the naming matches
  metadata: completed_batch.metadata.merge(
    ekn_id: ekn.id,
    neo4j_database: ekn.neo4j_database_name,
    postgres_schema: ekn.postgres_schema_name,
    isolation_enabled: true,
    migrated_at: Time.current
  )
)

puts "\n4. Data Migration Strategy:"
puts "   The Enliterator graph data already exists in the default Neo4j database."
puts "   To complete migration:"
puts "   a) Export nodes/relationships from default database"
puts "   b) Import into #{ekn.neo4j_database_name}"
puts "   c) Migrate PostgreSQL data to #{ekn.postgres_schema_name}"
puts "   d) Update Navigator to use the isolated EKN"

puts "\n5. Quick Neo4j Check:"
# Check what's in the default database
driver = Graph::Connection.instance.driver
session = driver.session # default database

result = session.run(<<~CYPHER)
  MATCH (n)
  RETURN labels(n)[0] as label, count(n) as count
  ORDER BY count DESC
  LIMIT 5
CYPHER

puts "   Current data in default database:"
result.each do |record|
  puts "     #{record['label']}: #{record['count']}"
end
session.close

# Check the isolated database
begin
  isolated_session = driver.session(database: ekn.neo4j_database_name)
  result = isolated_session.run("MATCH (n) RETURN count(n) as count")
  count = result.single['count']
  puts "\n   Data in isolated database #{ekn.neo4j_database_name}: #{count} nodes"
  isolated_session.close
rescue => e
  puts "\n   Isolated database check: #{e.message}"
end

puts "\n" + "="*80
puts "Meta-Enliterator EKN Created!"
puts "="*80
puts "\nNext Steps:"
puts "1. Run: rails runner script/migrate_meta_enliterator_data.rb"
puts "   This will copy the Enliterator-specific nodes from default to isolated database"
puts "\n2. Update Navigator configuration:"
puts "   Set @ekn = IngestBatch.find(#{ekn.id}) in NavigatorController"
puts "\n3. Test the isolated Knowledge Navigator:"
puts "   Visit http://localhost:3000 and ask about Enliterator's architecture"
puts "="*80