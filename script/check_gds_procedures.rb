#!/usr/bin/env ruby
# Check what GDS procedures are actually available

require_relative '../config/environment'

puts "\n🔍 Checking GDS procedures..."

driver = Graph::Connection.instance.driver
session = driver.session(database: 'neo4j')

begin
  # List all GDS procedures
  result = session.run(<<~CYPHER)
    SHOW PROCEDURES 
    YIELD name, signature 
    WHERE name STARTS WITH 'gds.' OR name STARTS WITH 'genai.'
    RETURN name, signature
    ORDER BY name
    LIMIT 30
  CYPHER
  
  procedures = result.to_a
  
  if procedures.any?
    puts "\n✅ Found #{procedures.count} GDS/GenAI procedures:"
    procedures.each do |p|
      puts "  - #{p[:name]}"
      puts "    #{p[:signature]}"
    end
  else
    puts "\n❌ No GDS or GenAI procedures found"
  end
  
  # Check specifically for vector/embedding related procedures
  puts "\n🔍 Checking for embedding-related procedures..."
  result = session.run(<<~CYPHER)
    SHOW PROCEDURES 
    YIELD name, signature 
    WHERE name CONTAINS 'vector' OR name CONTAINS 'embed' OR name CONTAINS 'encode'
    RETURN name, signature
    ORDER BY name
  CYPHER
  
  vector_procs = result.to_a
  
  if vector_procs.any?
    puts "\n✅ Found #{vector_procs.count} vector/embedding procedures:"
    vector_procs.each do |p|
      puts "  - #{p[:name]}"
    end
  else
    puts "❌ No vector/embedding procedures found"
  end

  # Check what functions are available
  puts "\n🔍 Checking GDS functions..."
  result = session.run(<<~CYPHER)
    SHOW FUNCTIONS
    YIELD name
    WHERE name STARTS WITH 'gds.' OR name STARTS WITH 'genai.'
    RETURN name
    ORDER BY name
    LIMIT 20
  CYPHER
  
  functions = result.to_a
  
  if functions.any?
    puts "\n✅ Found #{functions.count} GDS/GenAI functions:"
    functions.each do |f|
      puts "  - #{f[:name]}"
    end
  else
    puts "❌ No GDS/GenAI functions found"
  end

rescue => e
  puts "❌ Error: #{e.message}"
end

session.close

puts "\n📝 Note: The GenAI plugin procedures might be in a different namespace"
puts "   or require additional configuration to activate."