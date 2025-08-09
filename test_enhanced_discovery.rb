#!/usr/bin/env ruby

puts "=== Testing Enhanced Discovery Strategy ==="
puts "Goal: Achieve Stage 5.5 gates (mean degree ≥0.3, verb diversity ≥5)"
puts ""

batch = IngestBatch.find(76)
ekn = batch.ekn

# Run enhanced discovery
discovery = Graph::EnhancedDiscovery.new(ekn: ekn, batch: batch)

puts "=== Identifying Core Nodes ==="
core_nodes = discovery.identify_core_nodes(limit: 50)
puts "Found #{core_nodes.size} core nodes"

# Show pool distribution
pool_counts = core_nodes.group_by { |n| n[:pool] }.transform_values(&:count)
puts "Pool distribution:"
pool_counts.each do |pool, count|
  puts "  #{pool}: #{count}"
end

puts "\n=== Running Enhanced Discovery ==="
results = discovery.calculate_density_improvement

puts "\nDiscovery Results:"
puts "  Relationships discovered: #{results[:discovered]}"
puts "  Total edges: #{results[:edges_before]} → #{results[:edges_after]}"
puts "  Core nodes considered: #{results[:core_nodes]}"

puts "\n=== Metrics for Core Subgraph ==="
puts "  Density: #{results[:density]}"
puts "  Mean degree: #{results[:mean_degree]}"
puts "  Verb diversity: #{results[:verb_diversity]}"

puts "\n=== Stage 5.5 Gate Checks ==="
puts "  Mean degree ≥0.3: #{results[:gate_checks][:mean_degree] ? '✅ PASS' : '❌ FAIL'}"
puts "  Verb diversity ≥5: #{results[:gate_checks][:verb_diversity] ? '✅ PASS' : '❌ FAIL'}"

if results[:gate_checks].values.all?
  puts "\n🎉 ALL GATES PASSED! Ready to proceed to Stage 6."
else
  puts "\n⚠️  Gates not met. Need more aggressive discovery or fewer nodes."
end

# Show sample relationships
manager = Graph::RelationshipManager.new(ekn: ekn)
puts "\n=== Sample Verified Relationships ==="
verified = manager.list_verified(limit: 5)
verified.each_with_index do |rel, i|
  puts "#{i+1}. #{rel[:source][:label]} -[#{rel[:verb]}]-> #{rel[:target][:label]}"
end