#!/usr/bin/env ruby
# Test Neo4j connection with no authentication

require 'neo4j/driver'

puts "\n🔍 Testing Neo4j with authentication disabled..."

begin
  # Connect with no auth
  driver = Neo4j::Driver::GraphDatabase.driver(
    "bolt://100.104.170.10:8687",
    Neo4j::Driver::AuthTokens.none
  )
  
  session = driver.session
  result = session.run("RETURN 'Auth disabled works!' as msg, 1+1 as sum")
  data = result.single
  
  puts "✅ SUCCESS - No authentication needed!"
  puts "   Message: #{data[:msg]}"
  puts "   Math: #{data[:sum]}"
  
  # Check for GDS procedures
  puts "\n📋 Checking for GDS procedures..."
  result = session.run(<<~CYPHER)
    SHOW PROCEDURES 
    YIELD name 
    WHERE name STARTS WITH 'gds.' 
    RETURN count(name) as gds_count
  CYPHER
  
  gds_count = result.single[:gds_count]
  puts "   Found #{gds_count} GDS procedures"
  
  # Check for GenAI procedures
  puts "\n📋 Checking for GenAI procedures..."
  result = session.run(<<~CYPHER)
    SHOW PROCEDURES 
    YIELD name 
    WHERE name STARTS WITH 'genai.' OR name CONTAINS 'genai'
    RETURN name
    LIMIT 10
  CYPHER
  
  genai_procs = result.to_a
  if genai_procs.any?
    puts "✅ GenAI procedures found:"
    genai_procs.each { |p| puts "   - #{p[:name]}" }
  else
    puts "❌ No GenAI procedures found"
  end
  
  # List some available procedures
  puts "\n📋 Sample of available procedures:"
  result = session.run(<<~CYPHER)
    SHOW PROCEDURES 
    YIELD name 
    RETURN name 
    ORDER BY name 
    LIMIT 15
  CYPHER
  
  result.each { |r| puts "   - #{r[:name]}" }
  
  session.close
  driver.close
  
rescue => e
  puts "❌ Connection failed: #{e.message}"
  puts "\nTrying with empty credentials..."
  
  begin
    driver = Neo4j::Driver::GraphDatabase.driver(
      "bolt://100.104.170.10:8687",
      Neo4j::Driver::AuthTokens.basic("", "")
    )
    
    session = driver.session
    result = session.run("RETURN 'Empty auth works!' as msg")
    puts "✅ Empty credentials work: #{result.single[:msg]}"
    
    session.close
    driver.close
  rescue => e2
    puts "❌ Empty credentials also failed: #{e2.message}"
  end
end