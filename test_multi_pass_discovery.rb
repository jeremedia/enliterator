#!/usr/bin/env ruby

puts "=== Testing Multi-Pass Discovery ==="
puts "Starting at: #{Time.now}"
puts ""

batch = IngestBatch.find(76)
ekn = batch.ekn

# Get initial metrics
manager = Graph::RelationshipManager.new(ekn: ekn)
initial_metrics = manager.edge_metrics

puts "=== Initial Graph State ==="
puts "Total relationships: #{initial_metrics[:total]}"
puts "Verification rate: #{initial_metrics[:verification_rate]}%"
puts "Verb diversity: #{initial_metrics[:verified_verbs].keys.count}"
puts ""

# Run multi-pass discovery
puts "=== Starting Multi-Pass Discovery ==="
discovery = Graph::MultiPassDiscovery.new(ekn: ekn, batch: batch)
results = discovery.execute_all_passes

# Display results for each pass
puts "\n=== Pass Results ==="
results[:passes].each do |pass, data|
  puts "\n#{pass.to_s.upcase}:"
  puts "  Status: #{data[:status]}"
  puts "  Discovered: #{data[:discovered] || 0}" if data[:discovered]
  
  if data[:sample] && data[:sample].any?
    puts "  Sample relationships:"
    data[:sample].each do |rel|
      puts "    - #{rel[:source][:label]} -[#{rel[:verb]}]-> #{rel[:target][:label]}"
    end
  end
end

# Display final metrics
puts "\n=== Discovery Summary ==="
puts "Total relationships discovered: #{results[:total_discovered]}"

if results[:metrics]
  puts "\n=== Graph Metrics After Discovery ==="
  puts "Total edges: #{results[:metrics][:total_edges]}"
  puts "Total nodes: #{results[:metrics][:total_nodes]}"
  puts "Graph density: #{results[:metrics][:density]}"
  puts "Mean degree: #{results[:metrics][:mean_degree]}"
  puts "Verb diversity: #{results[:metrics][:verb_diversity]}"
end

# Compare before and after
final_metrics = manager.edge_metrics
puts "\n=== Before vs After ==="
puts "Relationships: #{initial_metrics[:total]} → #{final_metrics[:total]}"
puts "Increase: +#{final_metrics[:total] - initial_metrics[:total]}"

# Check if we're meeting Stage 5.5 gates
puts "\n=== Stage 5.5 Gate Check ==="
if results[:metrics]
  mean_degree = results[:metrics][:mean_degree]
  verb_diversity = results[:metrics][:verb_diversity]
  
  puts "Mean degree: #{mean_degree} (gate: ≥0.3) - #{mean_degree >= 0.3 ? '✅ PASS' : '❌ FAIL'}"
  puts "Verb diversity: #{verb_diversity} (gate: ≥5) - #{verb_diversity >= 5 ? '✅ PASS' : '❌ FAIL'}"
end

puts "\nCompleted at: #{Time.now}"