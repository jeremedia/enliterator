#!/usr/bin/env ruby
# Check available Neo4j procedures

require_relative '../config/environment'

driver = Graph::Connection.instance.driver
session = driver.session(database: 'neo4j')

puts "\n🔍 Checking for GenAI procedures in Neo4j..."

# Check all procedures
result = session.run(<<~CYPHER)
  CALL dbms.procedures() 
  YIELD name, signature, description
  WHERE name CONTAINS 'genai' OR name CONTAINS 'vector'
  RETURN name, signature, description
  ORDER BY name
CYPHER

procedures = result.to_a

if procedures.empty?
  puts "\n❌ No GenAI or vector procedures found!"
  puts "\n📋 Checking ALL available procedures (first 10)..."
  
  result = session.run(<<~CYPHER)
    CALL dbms.procedures() 
    YIELD name
    RETURN name
    ORDER BY name
    LIMIT 10
  CYPHER
  
  result.each do |r|
    puts "  - #{r[:name]}"
  end
  
  puts "\n⚠️  The GenAI plugin doesn't appear to be installed/loaded"
  puts "\n📝 To install GenAI plugin:"
  puts "1. Download from: https://github.com/neo4j/graph-data-science/releases"
  puts "2. Copy to Neo4j plugins directory"
  puts "3. Update neo4j.conf to allow procedures"
  puts "4. Restart Neo4j"
else
  puts "\n✅ Found #{procedures.count} GenAI/vector procedures:"
  procedures.each do |p|
    puts "\n  📌 #{p[:name]}"
    puts "     Signature: #{p[:signature]}"
    puts "     #{p[:description]}"
  end
end

# Check if we have GDS (Graph Data Science) which includes vector functions
puts "\n🔍 Checking for GDS procedures..."
result = session.run(<<~CYPHER)
  CALL dbms.procedures() 
  YIELD name
  WHERE name STARTS WITH 'gds.'
  RETURN count(name) as gds_count
CYPHER

gds_count = result.single[:gds_count]
if gds_count > 0
  puts "✅ GDS library found with #{gds_count} procedures"
  
  # Check for vector similarity functions
  result = session.run(<<~CYPHER)
    CALL dbms.functions() 
    YIELD name, signature
    WHERE name CONTAINS 'similarity' OR name CONTAINS 'vector'
    RETURN name, signature
    LIMIT 5
  CYPHER
  
  functions = result.to_a
  if functions.any?
    puts "\n📊 Vector/similarity functions available:"
    functions.each do |f|
      puts "  - #{f[:name]}: #{f[:signature]}"
    end
  end
else
  puts "❌ GDS library not found"
end

session.close

puts "\n💡 Alternative: We can use the REST API directly for embeddings"
puts "   Instead of genai.vector.encode, we can call OpenAI directly"
puts "   and store embeddings as array properties in Neo4j"