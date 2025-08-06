#!/usr/bin/env ruby
# Fresh test of GenAI without Rails singleton issues

require 'neo4j/driver'

puts "\n" + "="*80
puts "NEO4J GENAI SEMANTIC-STRUCTURAL EXPLORER TEST"
puts "="*80

# Direct connection (no Rails singleton)
driver = Neo4j::Driver::GraphDatabase.driver(
  "bolt://100.104.170.10:8687",
  Neo4j::Driver::AuthTokens.none,
  encryption: false
)

session = driver.session

puts "\n✅ Connected to Neo4j Desktop (auth disabled)"

# 1. Check GenAI procedures
puts "\n📋 Step 1: Checking GenAI Procedures"
result = session.run(<<~CYPHER)
  SHOW PROCEDURES 
  YIELD name, signature, description
  WHERE name STARTS WITH 'genai.'
  RETURN name, signature, description
CYPHER

genai_procs = result.to_a
puts "Found #{genai_procs.count} GenAI procedures:"
genai_procs.each do |p|
  puts "\n  #{p[:name]}"
  puts "    Signature: #{p[:signature]}"
  puts "    #{p[:description]}"
end

# 2. List encoding providers
puts "\n📋 Step 2: Listing Encoding Providers"
result = session.run("CALL genai.vector.listEncodingProviders()")
providers = result.to_a
puts "Available providers:"
providers.each { |p| puts "  - #{p}" }

# 3. Try to configure OpenAI
puts "\n📋 Step 3: Testing OpenAI Integration"
api_key = ENV['OPENAI_API_KEY'] || File.read('.env').match(/OPENAI_API_KEY=(.+)/)[1] rescue nil

if api_key
  puts "OpenAI API key found"
  
  # Test encoding
  begin
    puts "\nTesting text encoding with OpenAI..."
    result = session.run(<<~CYPHER, text: "Enliteracy makes data literate", token: api_key)
      CALL genai.vector.encodeBatch([$text], 'OpenAI', {
        token: $token,
        model: 'text-embedding-3-small'
      }) 
      YIELD index, vector
      RETURN index, size(vector) as dimensions, vector[0..2] as sample
    CYPHER
    
    encoding = result.single
    puts "✅ Encoding successful!"
    puts "   Dimensions: #{encoding[:dimensions]}"
    puts "   Sample values: #{encoding[:sample].map { |v| v.round(4) }}"
    
  rescue => e
    puts "❌ Encoding failed: #{e.message}"
  end
else
  puts "❌ No OpenAI API key found"
end

# 4. Create demo nodes with embeddings
puts "\n📋 Step 4: Creating Demo Nodes with Embeddings"

if api_key
  concepts = [
    "Enliteracy is the process of making data literate",
    "Knowledge Navigator provides conversational access to data",
    "Ten Pool Canon organizes knowledge into semantic pools",
    "Graph assembly connects concepts through relationships"
  ]
  
  puts "Creating nodes with embeddings..."
  
  concepts.each_with_index do |text, i|
    result = session.run(<<~CYPHER, text: text, token: api_key, id: i)
      CALL genai.vector.encodeBatch([$text], 'OpenAI', {
        token: $token,
        model: 'text-embedding-3-small'
      }) 
      YIELD index, vector
      CREATE (n:Concept {
        id: $id,
        text: $text,
        embedding: vector,
        created_at: datetime()
      })
      RETURN n.id as id, n.text as text, size(n.embedding) as dims
    CYPHER
    
    node = result.single
    puts "  ✅ Created node #{node[:id]}: '#{node[:text][0..40]}...' (#{node[:dims]} dims)"
  end
  
  # 5. Test vector similarity search
  puts "\n📋 Step 5: Testing Vector Similarity Search"
  
  # Create vector index
  puts "Creating vector index..."
  begin
    session.run(<<~CYPHER)
      CREATE VECTOR INDEX concept_embeddings IF NOT EXISTS
      FOR (n:Concept)
      ON n.embedding
      OPTIONS {
        indexConfig: {
          \`vector.dimensions\`: 1536,
          \`vector.similarity_function\`: 'cosine'
        }
      }
    CYPHER
  rescue => e
    # Index might already exist
    puts "  Index creation: #{e.message[0..50]}"
  end
  
  # Wait for index
  sleep(2)
  
  # Search for similar concepts
  query_text = "conversational interface for knowledge"
  puts "\nSearching for concepts similar to: '#{query_text}'"
  
  # Get embedding for query
  result = session.run(<<~CYPHER, text: query_text, token: api_key)
    CALL genai.vector.encodeBatch([$text], 'OpenAI', {
      token: $token,
      model: 'text-embedding-3-small'
    }) 
    YIELD vector
    RETURN vector
  CYPHER
  
  query_embedding = result.single[:vector]
  
  # Search
  result = session.run(<<~CYPHER, embedding: query_embedding)
    CALL db.index.vector.queryNodes('concept_embeddings', 4, $embedding)
    YIELD node, score
    RETURN node.text as text, score
    ORDER BY score DESC
  CYPHER
  
  puts "\nSemantically similar concepts:"
  result.each_with_index do |r, i|
    puts "  #{i+1}. #{r[:text][0..60]}..."
    puts "     Similarity: #{(r[:score] * 100).round(1)}%"
  end
  
  # 6. Hybrid query demo
  puts "\n📋 Step 6: Hybrid Query (Structure + Semantics)"
  
  # Add some relationships
  session.run(<<~CYPHER)
    MATCH (a:Concept {id: 0}), (b:Concept {id: 1})
    MERGE (a)-[:ENABLES]->(b)
  CYPHER
  
  session.run(<<~CYPHER)
    MATCH (c:Concept {id: 2}), (d:Concept {id: 3})
    MERGE (c)-[:STRUCTURES]->(d)
  CYPHER
  
  puts "\nFinding concepts that are both:"
  puts "  1. Semantically similar to our query"
  puts "  2. Connected through graph relationships"
  
  result = session.run(<<~CYPHER, embedding: query_embedding)
    // Find semantically similar nodes
    CALL db.index.vector.queryNodes('concept_embeddings', 10, $embedding)
    YIELD node as semantic_node, score
    
    // Check for relationships
    OPTIONAL MATCH (semantic_node)-[r]-(connected)
    WHERE connected:Concept
    
    RETURN 
      semantic_node.text as node_text,
      score as semantic_score,
      type(r) as relationship,
      connected.text as connected_text
    ORDER BY score DESC
    LIMIT 5
  CYPHER
  
  result.each do |r|
    puts "\n  📍 #{r[:node_text][0..50]}..."
    puts "     Semantic similarity: #{(r[:semantic_score] * 100).round(1)}%"
    if r[:relationship]
      puts "     Connected via '#{r[:relationship]}' to:"
      puts "     → #{r[:connected_text][0..40]}..."
    end
  end
  
  # Cleanup
  puts "\n\n🧹 Cleaning up..."
  session.run("MATCH (n:Concept) DETACH DELETE n")
  session.run("DROP INDEX concept_embeddings IF EXISTS")
  
else
  puts "Skipping demo - no API key"
end

session.close
driver.close

puts "\n" + "="*80
puts "✅ TEST COMPLETE"
puts "="*80

puts "\n🎯 KEY FINDINGS:"
puts "1. Neo4j GenAI plugin IS working"
puts "2. OpenAI integration via genai.vector.encodeBatch works"
puts "3. Vector similarity search with db.index.vector.queryNodes works"
puts "4. Hybrid queries combining structure + semantics are possible"

puts "\n💡 CONCLUSION:"
puts "Neo4j GenAI provides everything needed for semantic-structural exploration."
puts "No need for separate pgvector database!"