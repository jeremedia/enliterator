#!/usr/bin/env ruby

puts "=== Testing Spec-Compliant Discovery ==="
puts "Enforcing:"
puts "  - Closed verb glossary only"
puts "  - Neighbor sampling (k=8), not full pairwise"
puts "  - Real evidence requirements"
puts "  - Whole-graph metrics"
puts ""

batch = IngestBatch.find(76)
ekn = batch.ekn

# Get initial metrics
metrics_service = Graph::StageMetrics.new(ekn: ekn, batch: batch)
initial = metrics_service.calculate_graph_metrics

puts "=== Initial State ==="
puts "Nodes: #{initial[:total_nodes]}"
puts "Edges: #{initial[:total_edges]}"
puts "Mean degree: #{initial[:mean_degree]}"
puts ""

# Run spec-compliant discovery
discovery = Graph::SpecCompliantDiscovery.new(ekn: ekn, batch: batch)
results = discovery.discover_with_parity_check

puts "=== Discovery Results ==="
puts "Status: #{results[:status]}"
if results[:status] == 'failed'
  puts "Error: #{results[:error]}"
  puts "Parity: #{results[:parity]}"
  exit 1
end

puts "Attempted: #{results[:attempted]}"
puts "Created: #{results[:created]}"
puts "Parity rate: #{results[:parity_rate]}%"
puts ""

# Show corrected metrics
if results[:metrics]
  puts "=== Whole-Graph Metrics (Corrected) ==="
  puts "Total nodes: #{results[:metrics][:total_nodes]}"
  puts "Total edges: #{results[:metrics][:total_edges]}"
  puts "Mean degree: #{results[:metrics][:mean_degree]}"
  puts "Verified verb diversity: #{results[:metrics][:verified_verb_diversity]}"
  
  if results[:metrics][:verified_verbs].any?
    puts "Spec-compliant verified verbs:"
    results[:metrics][:verified_verbs].each do |verb|
      puts "  - #{verb}"
    end
  end
end

# Recalculate gates with corrected metrics
puts "\n=== Stage 5.5 Gate Status (Corrected) ==="
final_metrics = metrics_service.calculate_all_metrics
gates = final_metrics[:gate_status][:gates]

gates.each do |gate, result|
  status = result[:passed] ? "✅" : "❌"
  puts "#{gate}: #{result[:value]} (threshold: #{result[:threshold]}) #{status}"
end

# Check which verbs are actually in use
puts "\n=== Verb Compliance Check ==="
driver = Graph::Connection.instance.driver
driver.session(database: ekn.neo4j_database_name) do |session|
  session.read_transaction do |tx|
    query = <<~CYPHER
      MATCH ()-[r]->()
      WHERE type(r) <> 'HAS_RIGHTS'
      RETURN DISTINCT type(r) as verb
      ORDER BY verb
    CYPHER
    
    all_verbs = tx.run(query).map { |r| r['verb'] }
    
    spec_verbs = []
    non_spec_verbs = []
    
    all_verbs.each do |verb|
      if Graph::EdgeLoader::VERB_GLOSSARY.key?(verb.downcase)
        spec_verbs << verb
      else
        non_spec_verbs << verb
      end
    end
    
    puts "Spec-compliant verbs in use: #{spec_verbs.count}"
    spec_verbs.each { |v| puts "  ✅ #{v}" }
    
    if non_spec_verbs.any?
      puts "\nNON-SPEC VERBS FOUND (must be removed):"
      non_spec_verbs.each { |v| puts "  ❌ #{v}" }
    end
  end
end