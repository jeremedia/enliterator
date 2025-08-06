#!/usr/bin/env ruby
# Comprehensive diagnosis of Neo4j authentication issue

require 'neo4j/driver'
require 'json'
require 'net/http'

puts "\n" + "="*80
puts "NEO4J AUTHENTICATION DIAGNOSTIC REPORT"
puts "="*80
puts "Time: #{Time.now}"

# Test configurations
configs = [
  { name: "No Auth", auth: -> { Neo4j::Driver::AuthTokens.none } },
  { name: "Empty Credentials", auth: -> { Neo4j::Driver::AuthTokens.basic("", "") } },
  { name: "neo4j/neo4j", auth: -> { Neo4j::Driver::AuthTokens.basic("neo4j", "neo4j") } },
  { name: "neo4j/enliterator", auth: -> { Neo4j::Driver::AuthTokens.basic("neo4j", "enliterator") } },
  { name: "neo4j/cheese28", auth: -> { Neo4j::Driver::AuthTokens.basic("neo4j", "cheese28") } }
]

url = "bolt://100.104.170.10:8687"

puts "\n📋 1. BOLT CONNECTION TESTS"
puts "-" * 50
puts "Testing URL: #{url}"

results = {}
configs.each do |config|
  print "\n#{config[:name]}... "
  begin
    driver = Neo4j::Driver::GraphDatabase.driver(url, config[:auth].call)
    session = driver.session
    result = session.run("RETURN 1 as test")
    data = result.single
    
    if data[:test] == 1
      puts "✅ SUCCESS"
      results[config[:name]] = true
      
      # Check if we can see auth status
      begin
        auth_check = session.run("CALL dbms.showCurrentUser()")
        user = auth_check.single
        puts "   Current user: #{user[:username]}"
        puts "   Roles: #{user[:roles]}"
      rescue => e
        # This procedure might not exist
      end
    end
    
    session.close
    driver.close
  rescue => e
    puts "❌ FAILED"
    puts "   Error: #{e.message}"
    results[config[:name]] = false
  end
end

# Test HTTP endpoint
puts "\n\n📋 2. HTTP ENDPOINT TEST"
puts "-" * 50
uri = URI("http://100.104.170.10:8484/db/neo4j/tx")

# Test without auth
puts "\nTesting HTTP without auth..."
begin
  http = Net::HTTP.new(uri.host, uri.port)
  request = Net::HTTP::Post.new(uri)
  request['Content-Type'] = 'application/json'
  request.body = JSON.generate({
    statements: [{ statement: "RETURN 'http works' as msg" }]
  })
  
  response = http.request(request)
  if response.code == "200" || response.code == "201"
    puts "✅ HTTP works without authentication"
    data = JSON.parse(response.body)
    puts "   Result: #{data['results'][0]['data'][0]['row'][0]}" rescue nil
  else
    puts "❌ HTTP requires authentication (#{response.code})"
  end
rescue => e
  puts "❌ HTTP test failed: #{e.message}"
end

# Check config file
puts "\n\n📋 3. CONFIGURATION FILE CHECK"
puts "-" * 50
conf_path = "/Users/jeremy/Library/Application Support/neo4j-desktop/Application/Data/dbmss/dbms-3f4feab6-6708-46d6-ad3d-95c49ec730e5/conf/neo4j.conf"

if File.exist?(conf_path)
  puts "Config file exists: #{conf_path}"
  
  # Check auth settings
  auth_lines = File.readlines(conf_path).select { |line| line.include?("auth") && !line.start_with?("#") }
  
  puts "\nAuth-related settings:"
  auth_lines.each { |line| puts "   #{line.strip}" }
  
  if auth_lines.empty?
    puts "   (No auth settings found - using defaults)"
  end
else
  puts "❌ Config file not found"
end

# Check for multiple Neo4j instances
puts "\n\n📋 4. CHECKING FOR MULTIPLE NEO4J INSTANCES"
puts "-" * 50

# Check processes
neo4j_procs = `ps aux | grep -i neo4j | grep -v grep`
if neo4j_procs.empty?
  puts "No Neo4j processes found (might be in Docker/Desktop app)"
else
  puts "Neo4j processes:"
  neo4j_procs.lines.each { |line| puts "   #{line.split[10..].join(' ')[0..100]}..." }
end

# Check ports
puts "\nChecking ports:"
[7687, 8687, 7474, 8484].each do |port|
  listeners = `lsof -i :#{port} 2>/dev/null | grep LISTEN`
  if listeners.empty?
    puts "   Port #{port}: Not in use"
  else
    puts "   Port #{port}: #{listeners.lines.first.split[0]} (PID: #{listeners.lines.first.split[1]})"
  end
end

# Test both possible Neo4j instances
puts "\n\n📋 5. TESTING MULTIPLE ENDPOINTS"
puts "-" * 50

endpoints = [
  { url: "bolt://localhost:7687", name: "Homebrew Neo4j (default port)" },
  { url: "bolt://100.104.170.10:8687", name: "Neo4j Desktop (custom port)" }
]

endpoints.each do |endpoint|
  puts "\n#{endpoint[:name]} - #{endpoint[:url]}"
  
  # Try no auth first
  begin
    driver = Neo4j::Driver::GraphDatabase.driver(endpoint[:url], Neo4j::Driver::AuthTokens.none)
    session = driver.session
    result = session.run("CALL dbms.components() YIELD name, versions WHERE name = 'Neo4j Kernel' RETURN versions[0] as version")
    version = result.single[:version]
    puts "   ✅ Connected (no auth) - Version: #{version}"
    
    # Check if GDS/GenAI is available
    gds_check = session.run("SHOW PROCEDURES YIELD name WHERE name STARTS WITH 'gds.' RETURN count(name) as count")
    gds_count = gds_check.single[:count]
    
    genai_check = session.run("SHOW PROCEDURES YIELD name WHERE name STARTS WITH 'genai.' RETURN count(name) as count")
    genai_count = genai_check.single[:count]
    
    puts "   GDS procedures: #{gds_count}"
    puts "   GenAI procedures: #{genai_count}"
    
    session.close
    driver.close
  rescue => e
    puts "   ❌ Failed with no auth: #{e.message[0..100]}"
    
    # Try with password
    ['enliterator', 'cheese28', 'neo4j'].each do |pwd|
      begin
        driver = Neo4j::Driver::GraphDatabase.driver(
          endpoint[:url], 
          Neo4j::Driver::AuthTokens.basic("neo4j", pwd)
        )
        session = driver.session
        result = session.run("RETURN 1")
        puts "   ✅ Works with password: '#{pwd}'"
        session.close
        driver.close
        break
      rescue
        # Try next password
      end
    end
  end
end

# Rails environment check
puts "\n\n📋 6. RAILS ENVIRONMENT ANALYSIS"
puts "-" * 50

# Check if Rails is using singleton
puts "Rails singleton pattern issues:"
puts "   Graph::Connection uses Singleton pattern"
puts "   Singleton is initialized ONCE when Rails loads"
puts "   Changes to config/initializers/neo4j.rb require Rails restart"
puts "   Even reloading in console won't reset the singleton"

# Summary
puts "\n\n" + "="*80
puts "DIAGNOSIS SUMMARY"
puts "="*80

working_configs = results.select { |k, v| v }.keys
if working_configs.any?
  puts "\n✅ WORKING AUTHENTICATION METHODS:"
  working_configs.each { |c| puts "   - #{c}" }
else
  puts "\n❌ NO WORKING AUTHENTICATION METHODS FOUND"
end

puts "\n📊 FINDINGS:"
puts """
1. Authentication Status:
   - HTTP endpoint: #{results['HTTP'] ? 'No auth required' : 'Auth required'}
   - Bolt endpoint: #{results['No Auth'] ? 'No auth required' : 'Auth required'}
   
2. Configuration:
   - dbms.security.auth_enabled setting: #{auth_lines.any? { |l| l.include?('auth_enabled=false') } ? 'DISABLED' : 'ENABLED or DEFAULT'}
   
3. Possible Issues:
   - Neo4j Desktop might override config settings
   - Multiple Neo4j instances might be running
   - Rails singleton caching old credentials
   - Config file changes might not be taking effect
"""

puts "\n💡 RECOMMENDATIONS:"
if results['No Auth']
  puts "1. Auth IS disabled - use Neo4j::Driver::AuthTokens.none"
  puts "2. Restart Rails server to pick up config changes"
elsif results['neo4j/enliterator']
  puts "1. Auth is ENABLED - use password 'enliterator'"
  puts "2. Update Rails config with correct password"
  puts "3. Restart Rails server"
else
  puts "1. Try restarting Neo4j with auth truly disabled"
  puts "2. Or use the working credentials found above"
end