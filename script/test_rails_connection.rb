#!/usr/bin/env ruby
# Test Rails Neo4j connection with auth disabled

# Load Rails but CLEAR the singleton
require_relative '../config/environment'

# Force reload the connection
Graph::Connection.instance.close if Graph::Connection.instance.driver rescue nil
Singleton.__init__(Graph::Connection)

# Now test
puts "\n🔍 Testing Rails Neo4j connection..."

begin
  driver = Graph::Connection.instance.driver
  puts "✅ Driver created"
  
  session = driver.session
  result = session.run("RETURN 'Rails connection works!' as msg")
  data = result.single
  
  puts "✅ SUCCESS: #{data[:msg]}"
  
  # Test GenAI
  result = session.run("CALL genai.vector.listEncodingProviders()")
  providers = result.to_a
  
  puts "\n📋 GenAI providers available:"
  providers.each { |p| puts "   - #{p}" }
  
  session.close
rescue => e
  puts "❌ Failed: #{e.message}"
end