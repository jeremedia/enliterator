#!/usr/bin/env ruby

puts "=== Testing Hardening Improvements ==="
puts ""

batch = IngestBatch.find(76)
ekn = batch.ekn

# Test VerbPolicy
puts "=== Testing VerbPolicy ==="
test_cases = [
  { source: 'Idea', target: 'Manifest', verb: 'embodies', expected: true },
  { source: 'Idea', target: 'Practical', verb: 'codifies', expected: true },
  { source: 'Idea', target: 'Manifest', verb: 'relates_to', expected: true }, # Should normalize to influences
  { source: 'Idea', target: 'Manifest', verb: 'invalid_verb', expected: false }
]

test_cases.each do |test|
  result = Graph::VerbPolicy.allowed?(test[:source], test[:target], test[:verb])
  status = result == test[:expected] ? "✅" : "❌"
  normalized = Graph::VerbPolicy.normalize(test[:verb])
  puts "#{status} #{test[:source]}→#{test[:target]} [#{test[:verb]}]: #{result} (normalized: #{normalized})"
end

# Test bridge metrics
puts "\n=== Testing Bridge Metrics ==="
metrics_service = Graph::StageMetrics.new(ekn: ekn, batch: batch)
bridge_metrics = metrics_service.calculate_bridge_metrics
puts "Bridge count: #{bridge_metrics[:bridge_count]}"
puts "Recent edges: #{bridge_metrics[:recent_edges]}"
puts "Bridge rate: #{bridge_metrics[:bridge_rate]}%"
puts "Estimated bridge rate: #{bridge_metrics[:estimated_bridge_rate]}%"

# Run spec-compliant discovery with hardening
puts "\n=== Running Hardened Discovery ==="
discovery = Graph::SpecCompliantDiscovery.new(ekn: ekn, batch: batch)
results = discovery.discover_with_parity_check

if results[:status] == 'complete'
  puts "Status: #{results[:status]}"
  puts "Created: #{results[:created]} relationships"
  puts "Parity: #{results[:parity_rate]}%"
  
  if results[:metrics]
    puts "\nWhole-graph metrics:"
    puts "  Mean degree: #{results[:metrics][:mean_degree]}"
    puts "  Verified verbs: #{results[:metrics][:verified_verb_diversity]}"
  end
else
  puts "Discovery failed: #{results[:error]}"
end

# Check for bridges
puts "\n=== Checking Bridge Edges ==="
driver = Graph::Connection.instance.driver
driver.session(database: ekn.neo4j_database_name) do |session|
  session.read_transaction do |tx|
    query = <<~CYPHER
      MATCH ()-[r]->()
      WHERE r.bridge = true
      RETURN count(r) as bridge_count
    CYPHER
    
    result = tx.run(query).single
    puts "Total edges marked as bridges: #{result['bridge_count']}"
    
    # Sample some bridges
    sample_query = <<~CYPHER
      MATCH (s)-[r]->(t)
      WHERE r.bridge = true
      RETURN labels(s)[0] as source_pool, 
             labels(t)[0] as target_pool,
             type(r) as verb
      LIMIT 5
    CYPHER
    
    puts "\nSample bridge edges:"
    tx.run(sample_query).each do |row|
      puts "  #{row['source_pool']} -[#{row['verb']}]-> #{row['target_pool']}"
    end
  end
end

# Final metrics report
puts "\n=== Final Metrics Report ==="
all_metrics = metrics_service.calculate_all_metrics
puts metrics_service.generate_report