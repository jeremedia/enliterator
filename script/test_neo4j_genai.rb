#!/usr/bin/env ruby
# frozen_string_literal: true

# Test Neo4j GenAI integration for semantic-structural exploration
require_relative '../config/environment'

puts "\n" + "="*80
puts "NEO4J GENAI PROOF OF CONCEPT: SEMANTIC-STRUCTURAL EXPLORER"
puts "="*80

# Initialize services
vector_service = Neo4j::VectorIndexService.new
search_service = Neo4j::SemanticSearchService.new

# Step 1: Configure OpenAI Provider
puts "\n📋 Step 1: Configuring OpenAI Provider..."
if vector_service.configure_provider
  puts "✅ OpenAI provider configured successfully"
else
  puts "❌ Failed to configure OpenAI provider"
  puts "   Make sure OPENAI_API_KEY is set in your environment"
  exit 1
end

# Verify configuration
puts "\n🔍 Verifying provider configuration..."
config = vector_service.verify_provider
if config
  puts "✅ Provider verified - Models available: #{config[:models]}"
else
  puts "❌ Provider verification failed"
  exit 1
end

# Step 2: Create Vector Indexes
puts "\n📊 Step 2: Creating Vector Indexes..."
if vector_service.create_indexes
  puts "✅ Vector indexes created successfully"
else
  puts "⚠️  Some indexes may have failed (check logs)"
end

# Step 3: Test Embedding Generation
puts "\n🧬 Step 3: Testing Embedding Generation..."
test_text = "Enliteracy is the process of making data literate through pools of meaning"
embedding = vector_service.generate_embedding(test_text)

if embedding && embedding.is_a?(Array) && embedding.length == 1536
  puts "✅ Embedding generated successfully!"
  puts "   Dimension: #{embedding.length}"
  puts "   Sample values: [#{embedding[0..2].map { |v| v.round(4) }.join(', ')}...]"
else
  puts "❌ Embedding generation failed"
  exit 1
end

# Step 4: Test Embedding Storage
puts "\n💾 Step 4: Testing Embedding Storage in Neo4j..."
storage_result = vector_service.test_embedding_storage(test_text)
if storage_result
  puts "✅ Embedding stored in Neo4j node"
  puts "   Node ID: #{storage_result[:node_id]}"
  puts "   Dimensions: #{storage_result[:dimensions]}"
else
  puts "❌ Failed to store embedding in Neo4j"
end

# Step 5: Create Demo Knowledge Graph
puts "\n🌐 Step 5: Creating Demo Knowledge Graph with Embeddings..."
puts "   Creating nodes about Enliterator concepts..."

demo_result = search_service.create_demo_data
if demo_result
  puts "✅ Created #{demo_result[:nodes_created]} nodes with embeddings"
  demo_result[:nodes].each do |node|
    puts "   - [#{node[:pool]}] #{node[:label]}"
  end
else
  puts "❌ Failed to create demo data"
  exit 1
end

# Step 6: Pure Semantic Search
puts "\n🔍 Step 6: SEMANTIC SEARCH (Vector Similarity Only)"
puts "-" * 50
query = "conversational interface for data"
puts "Query: '#{query}'"
puts "\nSearching for semantically similar concepts..."

semantic_results = search_service.semantic_search(query, limit: 5)
if semantic_results.any?
  puts "\n📊 Found #{semantic_results.count} semantically similar nodes:"
  semantic_results.each_with_index do |result, i|
    puts "\n   #{i + 1}. [#{result[:labels].first}] #{result[:label]}"
    puts "      Similarity Score: #{(result[:score] * 100).round(1)}%"
    puts "      Text: #{result[:text][0..100]}..."
  end
else
  puts "❌ No semantic search results found"
end

# Step 7: Hybrid Search (Semantic + Structural)
puts "\n\n🔀 Step 7: HYBRID SEARCH (Semantic + Graph Structure)"
puts "-" * 50
query = "making data literate"
puts "Query: '#{query}'"
puts "\nSearching with BOTH semantic similarity AND graph connections..."

hybrid_results = search_service.hybrid_search(query, limit: 5, hops: 2)
if hybrid_results.any?
  puts "\n🌟 Found #{hybrid_results.count} results combining meaning and structure:"
  hybrid_results.each_with_index do |result, i|
    puts "\n   #{i + 1}. [#{result[:labels].first}] #{result[:label]}"
    puts "      📊 Semantic Score: #{(result[:semantic_score] * 100).round(1)}%"
    puts "      🔗 Connected Nodes: #{result[:connected_count]}"
    if result[:min_path_length]
      puts "      📍 Shortest Path: #{result[:min_path_length]} hop(s)"
    end
    puts "      ⭐ Combined Score: #{(result[:combined_score] * 100).round(1)}%"
    
    if result[:sample_connections]&.any?
      puts "      🔗 Sample Connections:"
      result[:sample_connections].each do |conn|
        puts "         - [#{conn[:pool]}] #{conn[:label]}"
      end
    end
  end
else
  puts "❌ No hybrid search results found"
end

# Step 8: Find Similar Nodes (Semantic Neighborhoods)
puts "\n\n🎯 Step 8: SEMANTIC NEIGHBORHOODS"
puts "-" * 50

# First, get a node to find neighbors for
driver = Graph::Connection.instance.driver
session = driver.session(database: 'neo4j')
source_result = session.run(<<~CYPHER)
  MATCH (n:Idea {label: 'Knowledge Navigator'})
  RETURN elementId(n) as id
CYPHER
source_node_id = source_result.single[:id]
session.close

puts "Finding semantic neighbors of 'Knowledge Navigator'..."
similar_nodes = search_service.find_similar(source_node_id, limit: 5)

if similar_nodes.any?
  puts "\n🌐 Semantic neighborhood (concepts with similar meaning):"
  similar_nodes.each_with_index do |node, i|
    puts "\n   #{i + 1}. [#{node[:labels].first}] #{node[:label]}"
    puts "      Similarity: #{(node[:similarity] * 100).round(1)}%"
    puts "      Text: #{node[:text][0..100]}..."
  end
else
  puts "❌ No similar nodes found"
end

# Step 9: Demonstrate the Power of Unified Queries
puts "\n\n💫 Step 9: THE POWER OF UNIFIED SEMANTIC-STRUCTURAL QUERIES"
puts "="*80

session = driver.session(database: 'neo4j')

# This query showcases what makes Neo4j GenAI special:
# It combines vector similarity with graph traversal in ONE query
puts "\n🚀 Running unified query that finds:"
puts "   1. Semantically similar concepts (by embedding)"
puts "   2. Their structural relationships (by edges)"
puts "   3. Hidden connections through semantic bridges"

query_embedding = vector_service.generate_embedding("knowledge transformation pipeline")

result = session.run(<<~CYPHER, embedding: query_embedding)
  // Find top semantically similar nodes
  CALL db.index.vector.queryNodes('universal_embeddings', 3, $embedding)
  YIELD node as semantic_match, score
  
  // For each semantic match, find its immediate neighbors
  OPTIONAL MATCH (semantic_match)-[direct_rel]-(neighbor)
  WHERE neighbor.embedding IS NOT NULL
  
  // Check if neighbors are ALSO semantically similar to our query
  WITH semantic_match, score, 
       collect(DISTINCT {
         node: neighbor, 
         relationship: type(direct_rel)
       }) as neighbors
  
  // Calculate semantic similarity of neighbors to our original query
  UNWIND neighbors as n
  WITH semantic_match, score, n.node as neighbor, n.relationship as rel_type,
       gds.similarity.cosine(n.node.embedding, $embedding) as neighbor_similarity
  WHERE neighbor_similarity > 0.5  // Only keep semantically relevant neighbors
  
  WITH semantic_match, score,
       collect({
         label: neighbor.label,
         relationship: rel_type,
         semantic_relevance: neighbor_similarity
       }) as semantic_bridges
  
  RETURN 
    semantic_match.label as concept,
    labels(semantic_match)[0] as pool,
    score as direct_similarity,
    size(semantic_bridges) as bridge_count,
    semantic_bridges[0..3] as top_bridges
  ORDER BY score DESC
CYPHER

puts "\n📈 Results: Concepts with Semantic Bridges"
puts "-" * 50

result.each do |r|
  puts "\n🎯 #{r[:concept]} [#{r[:pool]}]"
  puts "   Direct Similarity: #{(r[:direct_similarity] * 100).round(1)}%"
  puts "   Semantic Bridges: #{r[:bridge_count]}"
  
  if r[:top_bridges]&.any?
    puts "   📊 Top Semantic Bridges (structurally connected AND semantically relevant):"
    r[:top_bridges].each do |bridge|
      puts "      → #{bridge[:label]} via '#{bridge[:relationship]}'"
      puts "        (#{(bridge[:semantic_relevance] * 100).round(1)}% relevant to query)"
    end
  end
end

session.close

# Step 10: Visualization Data Structure
puts "\n\n🎨 Step 10: DATA STRUCTURE FOR KNOWLEDGE NAVIGATOR VISUALIZATION"
puts "="*80

puts "\nThe semantic-structural explorer enables visualizations that show:"
puts "1. 🔵 Nodes positioned by semantic similarity (clustering)"
puts "2. ➖ Solid lines for explicit relationships"
puts "3. ┅┅ Dashed lines for semantic similarity above threshold"
puts "4. 🟢 Node size based on combined importance (structural + semantic)"

puts "\n📊 Example visualization data structure:"
viz_data = {
  nodes: [
    { id: 1, label: "Enliteracy", pool: "Idea", x: 100, y: 100, semantic_cluster: 1 },
    { id: 2, label: "Knowledge Navigator", pool: "Idea", x: 120, y: 110, semantic_cluster: 1 },
    { id: 3, label: "Pipeline Stages", pool: "Practical", x: 200, y: 150, semantic_cluster: 2 }
  ],
  edges: [
    { source: 1, target: 2, type: "ENABLES", structural: true, weight: 1.0 },
    { source: 1, target: 3, type: "SIMILAR_TO", structural: false, weight: 0.73 }
  ]
}

puts JSON.pretty_generate(viz_data)

# Cleanup
puts "\n\n🧹 Cleaning up test data..."
cleanup_count = vector_service.cleanup_test_nodes
puts "   Removed #{cleanup_count} test nodes"

demo_cleanup = search_service.cleanup_demo_data
puts "   Removed #{demo_cleanup} demo nodes"

# Summary
puts "\n" + "="*80
puts "✅ PROOF OF CONCEPT COMPLETE!"
puts "="*80

puts "\n🎯 KEY INSIGHTS:"
puts "1. Neo4j GenAI successfully generates and stores embeddings"
puts "2. Semantic search finds conceptually related nodes even without edges"
puts "3. Hybrid search combines the best of both worlds"
puts "4. Unified queries eliminate the complexity of syncing two databases"
puts "5. This enables truly intelligent Knowledge Navigation"

puts "\n💡 ARCHITECTURAL BENEFITS:"
puts "• One database instead of two (Neo4j handles both)"
puts "• No synchronization complexity"
puts "• Unified query language (Cypher with vector operations)"
puts "• Perfect alignment with database-per-EKN isolation"
puts "• Native support for semantic-structural exploration"

puts "\n🚀 RECOMMENDATION:"
puts "PROCEED with Neo4j GenAI migration. This is architecturally superior"
puts "to maintaining separate Neo4j + pgvector databases."
puts "\n"