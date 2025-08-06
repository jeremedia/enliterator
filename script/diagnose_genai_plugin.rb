#!/usr/bin/env ruby
# Diagnose why GenAI plugin isn't loading

require_relative '../config/environment'

puts "\n" + "="*80
puts "NEO4J GENAI PLUGIN DIAGNOSTIC"
puts "="*80

driver = Graph::Connection.instance.driver
session = driver.session(database: 'neo4j')

# Step 1: Check what procedures ARE available
puts "\n📋 Step 1: Checking available procedures..."
begin
  # Try SHOW PROCEDURES (newer syntax)
  result = session.run("SHOW PROCEDURES YIELD name RETURN name ORDER BY name LIMIT 20")
  procedures = result.map { |r| r[:name] }
  
  puts "✅ Found #{procedures.count} procedures (first 20):"
  procedures.each { |p| puts "   - #{p}" }
  
  # Check for any genai procedures
  genai_procs = procedures.select { |p| p.include?('genai') }
  if genai_procs.any?
    puts "\n🎉 GenAI procedures found:"
    genai_procs.each { |p| puts "   - #{p}" }
  else
    puts "\n❌ No GenAI procedures found"
  end
  
rescue => e
  puts "❌ SHOW PROCEDURES failed: #{e.message}"
  
  # Try older dbms.procedures() syntax
  begin
    result = session.run("CALL dbms.procedures() YIELD name RETURN name LIMIT 10")
    puts "✅ dbms.procedures() works (older syntax)"
  rescue => e2
    puts "❌ dbms.procedures() also failed: #{e2.message}"
  end
end

# Step 2: Check what functions are available
puts "\n📋 Step 2: Checking available functions..."
begin
  result = session.run("SHOW FUNCTIONS YIELD name WHERE name CONTAINS 'vector' OR name CONTAINS 'embed' RETURN name")
  functions = result.map { |r| r[:name] }
  
  if functions.any?
    puts "✅ Found vector/embedding functions:"
    functions.each { |f| puts "   - #{f}" }
  else
    puts "❌ No vector/embedding functions found"
  end
rescue => e
  puts "❌ SHOW FUNCTIONS failed: #{e.message}"
end

# Step 3: Check if GDS is available (often bundled with GenAI)
puts "\n📋 Step 3: Checking for Graph Data Science (GDS) library..."
begin
  result = session.run("RETURN gds.version() as version")
  version = result.single[:version]
  puts "✅ GDS version: #{version}"
rescue => e
  puts "❌ GDS not available: #{e.message}"
end

# Step 4: Check Neo4j configuration
puts "\n📋 Step 4: Checking Neo4j configuration..."
begin
  result = session.run("CALL dbms.listConfig() YIELD name, value WHERE name CONTAINS 'procedure' OR name CONTAINS 'plugin' RETURN name, value")
  configs = result.to_a
  
  if configs.any?
    puts "📝 Relevant configuration:"
    configs.each do |c|
      puts "   #{c[:name]} = #{c[:value]}"
    end
  else
    puts "⚠️  No procedure/plugin configuration found"
  end
rescue => e
  puts "❌ Cannot read config: #{e.message}"
end

# Step 5: Try to call genai procedures directly
puts "\n📋 Step 5: Testing GenAI procedures directly..."

test_procedures = [
  "CALL genai.version()",
  "CALL genai.config.show()",
  "RETURN genai.vector.encode('test', 'OpenAI', {token: 'dummy'})"
]

test_procedures.each do |query|
  begin
    puts "\n   Testing: #{query}"
    result = session.run(query)
    puts "   ✅ Works!"
  rescue => e
    puts "   ❌ Failed: #{e.message.split('.').first}"
  end
end

session.close

puts "\n" + "="*80
puts "DIAGNOSIS COMPLETE"
puts "="*80

puts "\n📝 NEXT STEPS TO ENABLE GENAI PLUGIN:"
puts """
1. In Neo4j Desktop:
   - Stop your database
   - Click on your database
   - Go to 'Plugins' tab
   - Look for 'Neo4j GenAI' or 'Graph Data Science'
   - Click 'Install' if not installed
   - Click 'Enable' if installed but not enabled

2. In Settings tab, add these lines:
   dbms.security.procedures.unrestricted=genai.*,gds.*
   dbms.security.procedures.allowlist=genai.*,gds.*,apoc.*
   
3. Start your database again

4. If GenAI isn't in the plugin list:
   - Download from: https://neo4j.com/download-center/#algorithms
   - Or use: neo4j-admin plugin install genai
"""

puts "\n💡 ALTERNATIVE: Install via command line:"
puts """
# Find your Neo4j installation
neo4j_home=$(neo4j-admin server report | grep 'neo4j.home' | cut -d'=' -f2)

# Install GenAI plugin
neo4j-admin plugin install genai --verbose

# Or manually download and copy:
curl -L https://graphdatascience.ninja/neo4j-genai-processor-2.9.0.jar \\
  -o $neo4j_home/plugins/neo4j-genai-processor.jar

# Restart Neo4j
neo4j restart
"""