#!/usr/bin/env ruby
# Test Neo4j Desktop connection

require 'neo4j/driver'

configs = [
  { url: "bolt://100.104.170.10:8687", password: "enliterator", name: "Desktop Custom Port" },
  { url: "bolt://localhost:8687", password: "enliterator", name: "Localhost Custom Port" },
  { url: "bolt://localhost:7687", password: "cheese28", name: "Homebrew Default" }
]

puts "\n🔍 Testing Neo4j connections..."

configs.each do |config|
  puts "\n📋 Testing: #{config[:name]}"
  puts "   URL: #{config[:url]}"
  
  begin
    driver = Neo4j::Driver::GraphDatabase.driver(
      config[:url],
      Neo4j::Driver::AuthTokens.basic("neo4j", config[:password])
    )
    
    session = driver.session
    result = session.run("RETURN 'Connected!' as msg, 1+1 as sum")
    data = result.single
    
    puts "   ✅ SUCCESS!"
    puts "   Message: #{data[:msg]}"
    puts "   Math: #{data[:sum]}"
    
    # Check for GenAI
    begin
      result = session.run("CALL genai.version()")
      puts "   ✅ GenAI plugin available!"
    rescue => e
      if e.message.include?("genai.version")
        puts "   ⚠️  GenAI plugin not found"
      else
        puts "   ❌ GenAI check error: #{e.message}"
      end
    end
    
    session.close
    driver.close
    
  rescue => e
    puts "   ❌ FAILED: #{e.message}"
  end
end

puts "\n" + "="*50
puts "Use the working configuration in config/initializers/neo4j.rb"