#!/usr/bin/env ruby

batch = IngestBatch.find(76)
ekn = batch.ekn

clusterer = Graph::EntityClusterer.new(ekn: ekn, batch: batch)
struct_clusters = clusterer.identify_clusters(strategy: :structural)

puts "=== Analyzing #{struct_clusters.size} Structural Clusters ==="

# Check overlap between structural clusters
struct_clusters.each_with_index do |cluster, i|
  entity_ids = cluster[:entities].map { |e| e[:id] }
  
  puts "\nCluster #{i+1}: #{entity_ids.size} entities"
  
  # Check overlap with other clusters
  overlaps = []
  struct_clusters.each_with_index do |other, j|
    next if i == j
    other_ids = other[:entities].map { |e| e[:id] }
    overlap = (entity_ids & other_ids).size
    if overlap > 0
      overlap_pct = (overlap.to_f / entity_ids.size * 100).round(1)
      overlaps << "Cluster #{j+1}: #{overlap} entities (#{overlap_pct}%)"
    end
  end
  
  if overlaps.any?
    puts "  Overlaps with:"
    overlaps.each { |o| puts "    #{o}" }
  else
    puts "  No overlaps"
  end
end

puts "\n=== Problem Analysis ==="
puts "The structural clustering is finding graph neighborhoods (2-hop)."
puts "Since the graph is sparse, many neighborhoods overlap significantly."
puts "This causes aggressive deduplication."
puts "\nSolution: We need a different approach for sparse graphs."