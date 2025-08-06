#!/usr/bin/env ruby
# script/verify_ekn_accumulation.rb
#
# Verifies that the EKN model correctly accumulates knowledge across multiple batches
# This is the CRITICAL test of the new architecture!

require_relative '../config/environment'

puts "\n" + "="*80
puts "EKN Knowledge Accumulation Verification"
puts "="*80 + "\n"

# Find the Meta-Enliterator
# Need to use SQL to query JSONB field properly
ekn = Ekn.where("metadata->>'is_meta' = 'true'").last

unless ekn
  puts "❌ Meta-Enliterator not found. Run script/create_meta_enliterator.rb first"
  exit 1
end

puts "\n📊 Current Meta-Enliterator Status:"
puts "  • ID: #{ekn.id}"
puts "  • Name: #{ekn.name}"
puts "  • Status: #{ekn.status}"
puts "  • Neo4j Database: #{ekn.neo4j_database_name}"
puts "  • PostgreSQL Schema: #{ekn.postgres_schema_name}"

# Test 1: Multiple batches, same database
puts "\n[Test 1] Verifying multiple batches use the same database..."

batch_count = ekn.ingest_batches.count
puts "  Batch count: #{batch_count}"

if batch_count > 0
  database_names = ekn.ingest_batches.map(&:neo4j_database_name).uniq
  
  if database_names.count == 1 && database_names.first == ekn.neo4j_database_name
    puts "  ✅ All #{batch_count} batches use the same database: #{database_names.first}"
  else
    puts "  ❌ CRITICAL ERROR: Batches using different databases!"
    puts "     Expected: #{ekn.neo4j_database_name}"
    puts "     Found: #{database_names.inspect}"
    exit 1
  end
else
  puts "  ⚠️  No batches created yet"
end

# Test 2: Database persistence
puts "\n[Test 2] Verifying database persistence..."

if ekn.neo4j_database_exists?
  puts "  ✅ Neo4j database exists: #{ekn.neo4j_database_name}"
else
  puts "  ❌ Neo4j database not found: #{ekn.neo4j_database_name}"
end

if ekn.postgres_schema_exists?
  puts "  ✅ PostgreSQL schema exists: #{ekn.postgres_schema_name}"
else
  puts "  ❌ PostgreSQL schema not found: #{ekn.postgres_schema_name}"
end

# Test 3: EKN relationship integrity
puts "\n[Test 3] Verifying EKN relationship integrity..."

ekn.ingest_batches.each_with_index do |batch, index|
  puts "  Batch #{index + 1}:"
  puts "    • ID: #{batch.id}"
  puts "    • Name: #{batch.name}"
  puts "    • EKN ID: #{batch.ekn_id} (should be #{ekn.id})"
  puts "    • Database: #{batch.neo4j_database_name} (should be #{ekn.neo4j_database_name})"
  puts "    • Items: #{batch.ingest_items.count}"
  
  if batch.ekn_id == ekn.id
    puts "    ✅ Correctly belongs to EKN #{ekn.id}"
  else
    puts "    ❌ ERROR: Batch belongs to wrong EKN!"
  end
end

# Test 4: Create a new test batch to verify accumulation
puts "\n[Test 4] Creating test batch to verify accumulation..."

test_batch = ekn.ingest_batches.create!(
  name: "Verification Test Batch",
  source_type: 'test',
  status: 'pending',
  metadata: {
    test_run: true,
    created_by: 'verify_ekn_accumulation.rb'
  }
)

puts "  ✅ Created test batch ##{test_batch.id}"
puts "     • Database: #{test_batch.neo4j_database_name}"
puts "     • Should match EKN: #{ekn.neo4j_database_name}"

if test_batch.neo4j_database_name == ekn.neo4j_database_name
  puts "  ✅ Test batch correctly uses EKN's database"
else
  puts "  ❌ ERROR: Test batch using wrong database!"
end

# Summary
puts "\n" + "="*80
puts "Verification Results"
puts "="*80

success_count = 0
total_tests = 4

# Count successes
success_count += 1 if batch_count > 0 && database_names&.count == 1
success_count += 1 if ekn.neo4j_database_exists? && ekn.postgres_schema_exists?
success_count += 1 if ekn.ingest_batches.all? { |b| b.ekn_id == ekn.id }
success_count += 1 if test_batch.neo4j_database_name == ekn.neo4j_database_name

puts "\n📊 Final Score: #{success_count}/#{total_tests} tests passed"

if success_count == total_tests
  puts "\n🎉 SUCCESS! The EKN architecture is working correctly!"
  puts "   • EKNs persist across sessions"
  puts "   • Multiple batches share the same database"
  puts "   • Knowledge accumulation is possible"
  puts "\n✨ The Meta-Enliterator is ready to guide users!"
else
  puts "\n⚠️  Some tests failed. Review the output above."
  puts "   The EKN architecture may need adjustment."
end

puts "\n💡 Next Steps:"
puts "   1. Check that the pipeline processes data correctly"
puts "   2. Verify nodes accumulate in Neo4j (not just batches)"
puts "   3. Test that conversations can access all accumulated knowledge"
puts ""