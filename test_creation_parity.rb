#!/usr/bin/env ruby

puts "=== Testing Relationship Creation Parity ==="

batch = IngestBatch.find(76)
ekn = batch.ekn

# Clear existing relationships for clean test
driver = Graph::Connection.instance.driver
driver.session(database: ekn.neo4j_database_name) do |session|
  session.write_transaction do |tx|
    tx.run("MATCH ()-[r]->() WHERE type(r) <> 'HAS_RIGHTS' DELETE r")
  end
end

puts "Cleared existing relationships"

# Create a small set of test relationships
test_relationships = [
  {
    source: { pool_type: 'Idea', label: 'Community Innovation Framework' },
    target: { pool_type: 'Idea', label: 'Diverse perspectives' },
    verb: 'relates_to',
    confidence: 0.8,
    evidence_span: 'Both are framework concepts',
    discovery_stage: 'test',
    cluster_strategy: 'co_occurrence'
  },
  {
    source: { pool_type: 'Idea', label: 'Community Innovation Framework' },
    target: { pool_type: 'Practical', label: 'Continuous improvement.' },
    verb: 'codifies',
    confidence: 0.9,
    evidence_span: 'Framework guides improvement process',
    discovery_stage: 'test',
    cluster_strategy: 'semantic'
  },
  {
    source: { pool_type: 'Practical', label: 'prepare embeddings for downstream tasks' },
    target: { pool_type: 'Practical', label: 'Enable end-to-end fine-tuning of a base model with customer data.' },
    verb: 'supports',
    confidence: 0.7,
    evidence_span: 'Embeddings needed for fine-tuning',
    discovery_stage: 'test',
    cluster_strategy: 'structural'
  }
]

puts "\nAttempting to create #{test_relationships.size} relationships..."

created_count = 0
failed_count = 0

driver.session(database: ekn.neo4j_database_name) do |session|
  session.write_transaction do |tx|
    # Mock pipeline job's create method
    job = Graph::RelationshipDiscoveryJob.new
    job.instance_variable_set(:@ekn, ekn)
    job.instance_variable_set(:@batch, batch)
    
    test_relationships.each_with_index do |rel, i|
      begin
        result = job.send(:create_graph_relationship, tx, rel)
        if result
          created_count += 1
          puts "  ✅ Created relationship #{i+1}"
        else
          failed_count += 1
          puts "  ⚠️  Skipped relationship #{i+1} (nodes missing)"
        end
      rescue => e
        failed_count += 1
        puts "  ❌ Failed relationship #{i+1}: #{e.message}"
      end
    end
  end
end

# Count actual relationships in Neo4j
actual_count = 0
driver.session(database: ekn.neo4j_database_name) do |session|
  session.read_transaction do |tx|
    result = tx.run("MATCH ()-[r]->() WHERE type(r) <> 'HAS_RIGHTS' RETURN count(r) as count")
    actual_count = result.single['count']
  end
end

puts "\n" + "="*60
puts "PARITY TEST RESULTS"
puts "="*60
puts "Relationships attempted: #{test_relationships.size}"
puts "Relationships created:   #{created_count}"
puts "Relationships failed:    #{failed_count}"
puts "Actual in Neo4j:        #{actual_count}"
puts ""

if test_relationships.size == created_count && created_count == actual_count
  puts "✅ FULL PARITY ACHIEVED"
  puts "All attempted relationships successfully created"
else
  puts "❌ PARITY MISMATCH"
  puts "Discrepancy: attempted(#{test_relationships.size}) != created(#{created_count}) != actual(#{actual_count})"
end
puts "="*60