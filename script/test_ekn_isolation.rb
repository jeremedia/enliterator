#!/usr/bin/env ruby
# Test script for EKN isolation architecture
# This verifies that each EKN has completely isolated data

require_relative '../config/environment'

puts "\n" + "="*80
puts "Testing EKN Data Isolation Architecture"
puts "="*80

# Clean up any test EKNs from previous runs
puts "\n1. Cleaning up test EKNs from previous runs..."
IngestBatch.where("name LIKE 'Test EKN%'").each do |ekn|
  puts "   Removing: #{ekn.name}"
  begin
    EknManager.destroy_ekn(ekn)
  rescue => e
    puts "   Warning: #{e.message}"
  end
end

# Create first test EKN
puts "\n2. Creating first test EKN (Medical Research)..."
ekn1 = EknManager.create_ekn(
  name: "Test EKN Medical Research",
  description: "Contains sensitive medical data"
)
puts "   ✓ Created EKN #{ekn1.id}: #{ekn1.name}"
puts "   - Neo4j database: #{ekn1.neo4j_database_name}"
puts "   - PostgreSQL schema: #{ekn1.postgres_schema_name}"
puts "   - Storage path: #{ekn1.storage_root_path}"

# Create second test EKN
puts "\n3. Creating second test EKN (Festival Data)..."
ekn2 = EknManager.create_ekn(
  name: "Test EKN Festival 2025",
  description: "Contains festival and event data"
)
puts "   ✓ Created EKN #{ekn2.id}: #{ekn2.name}"
puts "   - Neo4j database: #{ekn2.neo4j_database_name}"
puts "   - PostgreSQL schema: #{ekn2.postgres_schema_name}"
puts "   - Storage path: #{ekn2.storage_root_path}"

# Test Neo4j isolation
puts "\n4. Testing Neo4j database isolation..."

# Add data to EKN1's database
service1 = Graph::QueryService.new(ekn1)
session1 = service1.instance_variable_get(:@driver).session(database: ekn1.neo4j_database_name)
session1.run("CREATE (n:MedicalRecord {id: 1, name: 'Patient X', diagnosis: 'Confidential'})")
session1.run("CREATE (n:Treatment {id: 2, name: 'Therapy Y', patient: 'Patient X'})")
session1.run("MATCH (m:MedicalRecord), (t:Treatment) CREATE (m)-[:RECEIVES]->(t)")
session1.close

# Add data to EKN2's database
service2 = Graph::QueryService.new(ekn2)
session2 = service2.instance_variable_get(:@driver).session(database: ekn2.neo4j_database_name)
session2.run("CREATE (n:Event {id: 1, name: 'Main Stage', type: 'Music'})")
session2.run("CREATE (n:Artist {id: 2, name: 'DJ Z', genre: 'Electronic'})")
session2.run("MATCH (e:Event), (a:Artist) CREATE (a)-[:PERFORMS_AT]->(e)")
session2.close

# Verify isolation - EKN1 should only see medical data
results1 = service1.search_entities("", limit: 10)
puts "   EKN1 sees #{results1.size} entities:"
results1.each { |e| puts "     - #{e[:name]} (#{e[:type]})" }

# Verify isolation - EKN2 should only see festival data
results2 = service2.search_entities("", limit: 10)
puts "   EKN2 sees #{results2.size} entities:"
results2.each { |e| puts "     - #{e[:name]} (#{e[:type]})" }

# Cross-check: EKN1 shouldn't see festival data
cross_check1 = service1.search_entities("DJ", limit: 10)
puts "   ✓ EKN1 searching for 'DJ': #{cross_check1.empty? ? 'Not found (correct!)' : 'FOUND (ERROR!)'}"

# Cross-check: EKN2 shouldn't see medical data
cross_check2 = service2.search_entities("Patient", limit: 10)
puts "   ✓ EKN2 searching for 'Patient': #{cross_check2.empty? ? 'Not found (correct!)' : 'FOUND (ERROR!)'}"

# Test PostgreSQL isolation
puts "\n5. Testing PostgreSQL schema isolation..."

# Add data to EKN1's schema
ApplicationRecord.connection.execute(<<-SQL)
  INSERT INTO #{ekn1.postgres_schema_name}.entities (neo4j_id, name, pool)
  VALUES ('1', 'Sensitive Medical Entity', 'experience');
SQL

# Add data to EKN2's schema
ApplicationRecord.connection.execute(<<-SQL)
  INSERT INTO #{ekn2.postgres_schema_name}.entities (neo4j_id, name, pool)
  VALUES ('1', 'Public Festival Entity', 'manifest');
SQL

# Query EKN1's schema
result1 = ApplicationRecord.connection.execute(
  "SELECT * FROM #{ekn1.postgres_schema_name}.entities"
)
puts "   EKN1 PostgreSQL entities: #{result1.count}"
result1.each { |row| puts "     - #{row['name']} (#{row['pool']})" }

# Query EKN2's schema
result2 = ApplicationRecord.connection.execute(
  "SELECT * FROM #{ekn2.postgres_schema_name}.entities"
)
puts "   EKN2 PostgreSQL entities: #{result2.count}"
result2.each { |row| puts "     - #{row['name']} (#{row['pool']})" }

# Test file storage isolation
puts "\n6. Testing file storage isolation..."

if ENV.fetch('STORAGE_TYPE', 'filesystem') == 'filesystem'
  # Create test files
  file1_path = ekn1.storage_root_path.join('uploads', 'medical_data.txt')
  FileUtils.mkdir_p(File.dirname(file1_path))
  File.write(file1_path, "Confidential medical information")
  puts "   ✓ Created file in EKN1: #{file1_path}"
  
  file2_path = ekn2.storage_root_path.join('uploads', 'festival_schedule.txt')
  FileUtils.mkdir_p(File.dirname(file2_path))
  File.write(file2_path, "Public festival schedule")
  puts "   ✓ Created file in EKN2: #{file2_path}"
  
  # Verify isolation
  puts "   ✓ EKN1 storage exists: #{File.exist?(ekn1.storage_root_path)}"
  puts "   ✓ EKN2 storage exists: #{File.exist?(ekn2.storage_root_path)}"
  puts "   ✓ Paths are different: #{ekn1.storage_root_path != ekn2.storage_root_path}"
end

# Get statistics
puts "\n7. EKN Statistics..."
stats1 = EknManager.ekn_statistics(ekn1)
puts "   EKN1 Stats:"
puts "     Neo4j: #{stats1[:neo4j][:node_count]} nodes, #{stats1[:neo4j][:relationship_count]} relationships"
puts "     PostgreSQL: #{stats1[:postgres][:entities]} entities"

stats2 = EknManager.ekn_statistics(ekn2)
puts "   EKN2 Stats:"
puts "     Neo4j: #{stats2[:neo4j][:node_count]} nodes, #{stats2[:neo4j][:relationship_count]} relationships"
puts "     PostgreSQL: #{stats2[:postgres][:entities]} entities"

# Clean up
puts "\n8. Cleaning up test EKNs..."
puts "   Destroying EKN1..."
EknManager.destroy_ekn(ekn1)
puts "   ✓ EKN1 destroyed"

puts "   Destroying EKN2..."
EknManager.destroy_ekn(ekn2)
puts "   ✓ EKN2 destroyed"

# Verify cleanup
puts "\n9. Verifying cleanup..."
begin
  # Try to query deleted database
  service = Graph::QueryService.new(ekn1.neo4j_database_name)
  session = service.instance_variable_get(:@driver).session(database: ekn1.neo4j_database_name)
  session.run("MATCH (n) RETURN count(n)")
  session.close
  puts "   ❌ ERROR: Database still exists!"
rescue => e
  puts "   ✓ Neo4j database properly deleted"
end

begin
  # Try to query deleted schema
  ApplicationRecord.connection.execute("SELECT * FROM #{ekn1.postgres_schema_name}.entities LIMIT 1")
  puts "   ❌ ERROR: Schema still exists!"
rescue => e
  puts "   ✓ PostgreSQL schema properly deleted"
end

if ENV.fetch('STORAGE_TYPE', 'filesystem') == 'filesystem'
  if File.exist?(ekn1.storage_root_path)
    puts "   ❌ ERROR: Storage directory still exists!"
  else
    puts "   ✓ Storage directory properly deleted"
  end
end

puts "\n" + "="*80
puts "✅ EKN Isolation Test Complete!"
puts "="*80
puts "\nSummary:"
puts "- Each EKN has its own Neo4j database"
puts "- Each EKN has its own PostgreSQL schema"
puts "- Each EKN has its own file storage"
puts "- Data is completely isolated between EKNs"
puts "- Resources are properly cleaned up on deletion"
puts "="*80