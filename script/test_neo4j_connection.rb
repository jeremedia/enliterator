#!/usr/bin/env ruby
# Test basic Neo4j connection

require_relative '../config/environment'

puts "\n🔍 Testing Neo4j connection..."

driver = Graph::Connection.instance.driver
session = driver.session(database: 'neo4j')

begin
  # Simple test query
  result = session.run("RETURN 'Neo4j is working!' as message, 1 + 1 as sum")
  data = result.single
  
  puts "✅ Neo4j connection successful!"
  puts "   Message: #{data[:message]}"
  puts "   Math check: 1 + 1 = #{data[:sum]}"
  
  # Check Neo4j version
  result = session.run("CALL dbms.components() YIELD name, versions WHERE name = 'Neo4j Kernel' RETURN versions[0] as version")
  version = result.single[:version]
  puts "   Neo4j version: #{version}"
  
rescue => e
  puts "❌ Connection test failed: #{e.message}"
  
  # Try a simpler query
  begin
    result = session.run("RETURN 1 as test")
    puts "✅ Basic query works, but system procedures may be restricted"
  rescue => e2
    puts "❌ Even basic queries fail: #{e2.message}"
  end
end

session.close

puts "\n📝 Alternative approach: Use OpenAI directly for embeddings"
puts "   We can call OpenAI API directly and store embeddings as arrays in Neo4j"
puts "   This gives us the same functionality without requiring GenAI plugin"