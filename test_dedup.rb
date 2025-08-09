#!/usr/bin/env ruby

batch = IngestBatch.find(76)
ekn = batch.ekn

clusterer = Graph::EntityClusterer.new(ekn: ekn, batch: batch)

# Get clusters from each strategy
co_clusters = clusterer.identify_clusters(strategy: :co_occurrence)
struct_clusters = clusterer.identify_clusters(strategy: :structural)

puts "=== Before Deduplication ==="
puts "Co-occurrence: #{co_clusters.size} clusters"
puts "Structural: #{struct_clusters.size} clusters"

# Combine them
all_clusters = co_clusters + struct_clusters
puts "Combined: #{all_clusters.size} clusters"

# Show entity overlap
co_entities = co_clusters.flat_map { |c| c[:entities].map { |e| e[:id] } }.uniq
struct_entities = struct_clusters.flat_map { |c| c[:entities].map { |e| e[:id] } }.uniq
overlap = co_entities & struct_entities

puts "\n=== Entity Coverage ==="
puts "Co-occurrence covers: #{co_entities.size} entities"
puts "Structural covers: #{struct_entities.size} entities"
puts "Overlap: #{overlap.size} entities"
puts "Total unique: #{(co_entities | struct_entities).size} entities"

# Manual deduplication test
puts "\n=== Testing Deduplication Logic ==="

# Simulate what deduplicate_clusters does
by_strategy = all_clusters.group_by { |c| c[:strategy] }
puts "Grouped by strategy:"
by_strategy.each do |strategy, clusters|
  puts "  #{strategy}: #{clusters.size} clusters"
end

# Check the actual deduplication
deduped = clusterer.send(:deduplicate_clusters, all_clusters)
puts "\n=== After Deduplication ==="
puts "Result: #{deduped.size} clusters"

by_strategy = deduped.group_by { |c| c[:strategy] }
by_strategy.each do |strategy, clusters|
  puts "  #{strategy}: #{clusters.size} clusters"
end

# Show what got removed
removed = all_clusters.size - deduped.size
puts "\n#{removed} clusters were removed by deduplication"