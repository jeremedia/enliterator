#!/usr/bin/env ruby

batch = IngestBatch.find(76)
ekn = batch.ekn

puts "=== Testing Relationship Discovery with ALL Clusters ==="

# Get all clusters without deduplication
clusterer = Graph::EntityClusterer.new(ekn: ekn, batch: batch)
all_clusters = []

[:co_occurrence, :structural].each do |strategy|
  begin
    clusters = clusterer.identify_clusters(strategy: strategy)
    all_clusters.concat(clusters)
    puts "#{strategy}: Added #{clusters.size} clusters"
  rescue => e
    puts "#{strategy}: ERROR - #{e.message}"
  end
end

puts "\nTotal clusters to process: #{all_clusters.size}"
puts "Total unique entities involved: #{all_clusters.flat_map { |c| c[:entities].map { |e| e[:id] } }.uniq.size}"

# Simulate relationship discovery for all clusters
total_potential_relationships = 0
all_clusters.each_with_index do |cluster, i|
  entity_count = cluster[:entities].size
  # Estimate: each entity could relate to others in cluster
  potential_relationships = (entity_count * (entity_count - 1)) / 2
  total_potential_relationships += potential_relationships
  
  if i < 5  # Show first 5 clusters
    puts "Cluster #{i+1}: #{entity_count} entities → ~#{potential_relationships} potential relationships"
  end
end

puts "\n=== Potential Impact ==="
puts "If we process all #{all_clusters.size} clusters:"
puts "Estimated relationships: #{total_potential_relationships}"
puts "Current node count: 5169"
puts "Potential density: #{'%.4f' % (total_potential_relationships.to_f / 5169)}"

# Actually process a larger structural cluster
puts "\n=== Testing Larger Cluster Processing ==="
structural_clusters = clusterer.identify_clusters(strategy: :structural)
if structural_clusters.any?
  largest = structural_clusters.max_by { |c| c[:entities].size }
  puts "Processing largest structural cluster with #{largest[:entities].size} entities..."
  
  # Prepare for extraction
  entities = largest[:entities].map do |e|
    {
      pool_type: e[:pool_type] || e[:labels].first,
      label: e[:label],
      id: e[:id].to_s
    }
  end
  
  # Build context (use repr_text if available)
  content = entities.map { |e| "#{e[:pool_type]}: #{e[:label]}" }.join(". ")
  
  # Extract relationships
  service = Pools::RelationExtractionService.new(
    content: content,
    entities: entities
  )
  
  result = service.extract
  if result[:success]
    puts "Extracted #{result[:relations].size} relationships from this cluster!"
    puts "This single cluster could add #{result[:relations].size} relationships"
  else
    puts "Extraction failed: #{result[:error]}"
  end
end