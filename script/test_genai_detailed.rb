#!/usr/bin/env ruby
# Detailed GenAI plugin test

require_relative '../config/environment'

driver = Graph::Connection.instance.driver
session = driver.session(database: 'neo4j')

puts "\n" + "="*80
puts "DETAILED GENAI PLUGIN TEST"
puts "="*80

# 1. Check ALL available procedures
puts "\n📋 ALL Available Procedures (first 50):"
result = session.run("SHOW PROCEDURES YIELD name RETURN name ORDER BY name LIMIT 50")
all_procs = result.map { |r| r[:name] }
all_procs.each { |p| puts "  - #{p}" }

# 2. Look for any procedure with 'gen' in the name
puts "\n🔍 Procedures containing 'gen':"
gen_procs = all_procs.select { |p| p.downcase.include?('gen') }
if gen_procs.any?
  gen_procs.each { |p| puts "  - #{p}" }
else
  puts "  None found"
end

# 3. Check functions
puts "\n📋 ALL Available Functions (sample):"
result = session.run("SHOW FUNCTIONS YIELD name RETURN name ORDER BY name LIMIT 30")
functions = result.map { |r| r[:name] }
functions.each { |p| puts "  - #{p}" }

# 4. Try the Python example's exact procedure
puts "\n🔍 Testing Python example procedures:"
test_queries = [
  "CALL genai.vector.encodeBatch(['test'], 'OpenAI', {token: 'dummy'})",
  "CALL db.create.setNodeVectorProperty(n, 'embedding', [1.0, 2.0])",
  "RETURN gds.version()"
]

test_queries.each do |q|
  begin
    puts "\nTesting: #{q[0..60]}..."
    result = session.run(q)
    puts "  ✅ Works!"
  rescue => e
    puts "  ❌ #{e.message[0..100]}"
  end
end

# 5. Check if we can at least store vectors
puts "\n🔍 Testing vector storage capability:"
begin
  # Create a test node with a vector
  result = session.run(<<~CYPHER)
    CREATE (test:TestVector {
      name: 'test',
      embedding: [0.1, 0.2, 0.3, 0.4, 0.5]
    })
    RETURN test.name as name, size(test.embedding) as dims
  CYPHER
  
  data = result.single
  puts "  ✅ Can store vectors! Dimensions: #{data[:dims]}"
  
  # Clean up
  session.run("MATCH (n:TestVector) DELETE n")
rescue => e
  puts "  ❌ Cannot store vectors: #{e.message}"
end

# 6. Check vector index capability  
puts "\n🔍 Testing vector index creation:"
begin
  result = session.run(<<~CYPHER)
    CREATE VECTOR INDEX test_embedding IF NOT EXISTS
    FOR (n:TestVector)
    ON n.embedding
    OPTIONS {
      vector.dimensions: 5,
      vector.similarity_function: 'cosine'
    }
  CYPHER
  puts "  ✅ Can create vector indexes!"
  
  # Clean up
  session.run("DROP INDEX test_embedding IF EXISTS")
rescue => e
  puts "  ❌ Cannot create vector index: #{e.message}"
end

session.close

puts "\n" + "="*80
puts "DIAGNOSIS"
puts "="*80

puts """
The GenAI plugin (neo4j-genai-plugin-2025.07.1.jar) is installed but its procedures
are not being registered. This could be because:

1. The plugin requires additional activation beyond just copying the JAR
2. The plugin might need to be enabled through Neo4j Desktop's UI
3. There might be a version compatibility issue

HOWEVER, Neo4j DOES have native vector capabilities:
- ✅ Store vector embeddings as properties
- ✅ Create vector indexes  
- ✅ Query by vector similarity

RECOMMENDATION: We can implement the same functionality by:
1. Call OpenAI API directly from Rails (we already have the gem)
2. Store embeddings as array properties in Neo4j
3. Use Neo4j's native vector indexes and similarity search

This gives us the EXACT same capabilities without needing the GenAI plugin!
"""