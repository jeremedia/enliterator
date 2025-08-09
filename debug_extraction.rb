#!/usr/bin/env ruby

batch = IngestBatch.find(76)
ekn = batch.ekn

clusterer = Graph::EntityClusterer.new(ekn: ekn, batch: batch)
structural_clusters = clusterer.identify_clusters(strategy: :structural)

puts "=== Testing Structural Cluster Extraction ==="
puts "Found #{structural_clusters.size} structural clusters"

# Test the first few structural clusters
structural_clusters.first(3).each_with_index do |cluster, i|
  puts "\n=== Cluster #{i+1}: #{cluster[:entities].size} entities ==="
  
  # Build context as the job does
  context_parts = []
  cluster[:entities].each do |entity|
    label = entity[:label]
    pool = entity[:pool_type] || entity[:labels]&.first
    context_parts << "#{pool.to_s.capitalize}: #{label}"
    if entity[:repr_text].present?
      context_parts << entity[:repr_text]
    end
  end
  
  context_parts << "\nThese entities are connected in the knowledge graph through existing relationships."
  context_parts << "They form a neighborhood of related concepts that likely have additional semantic connections."
  context_parts << "\nAnalyze the connections between these entities using verbs like: embodies, elicits, codifies, exemplifies, influences, necessitates, manifests_as."
  
  content = context_parts.join("\n\n").truncate(8000)
  
  puts "Context length: #{content.length} chars"
  puts "First 500 chars of context:"
  puts content[0..500]
  
  # Try extraction
  entities = cluster[:entities].map do |e|
    {
      pool_type: e[:pool_type] || e[:labels]&.first,
      label: e[:label],
      id: e[:id].to_s
    }
  end
  
  service = Pools::RelationExtractionService.new(
    content: content,
    entities: entities
  )
  
  result = service.extract
  
  if result[:success]
    puts "\nExtracted #{result[:relations].size} relationships"
    if result[:relations].any?
      result[:relations].first(3).each do |rel|
        puts "  #{rel[:source][:label]} -[#{rel[:verb]}]-> #{rel[:target][:label]}"
      end
    end
  else
    puts "\nExtraction failed: #{result[:error]}"
  end
end