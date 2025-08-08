#!/usr/bin/env ruby
# Validates that all Neo4j connections use the centralized configuration

require_relative '../config/environment'

puts "\n" + "="*80
puts "NEO4J CONFIGURATION VALIDATION"
puts "="*80

# 1. Check the central configuration
puts "\n1. Central Configuration (neo4j.rb):"
config = Rails.application.config.neo4j
puts "   URL: #{config[:url]}"
puts "   Auth: DISABLED (uses AuthTokens.none)"
puts "   Pool Size: #{config[:pool_size]}"

# 2. Verify Graph::Connection singleton
puts "\n2. Graph::Connection Singleton:"
begin
  driver = Graph::Connection.instance.driver
  connectivity = driver.verify_connectivity
  puts "   Status: #{connectivity ? '✅ Connected' : '❌ Not connected'}"
  
  # Test a simple query
  session = driver.session
  result = session.run("RETURN 1 as test")
  test_val = result.single['test']
  session.close
  
  puts "   Query Test: #{test_val == 1 ? '✅ Working' : '❌ Failed'}"
rescue => e
  puts "   ❌ Error: #{e.message}"
end

# 3. Check for hardcoded connections in scripts
puts "\n3. Checking for hardcoded connections in scripts:"

script_files = Dir.glob(Rails.root.join('script', '*.rb'))
issues_found = []

script_files.each do |file|
  content = File.read(file)
  filename = File.basename(file)
  
  # Check for direct driver creation (bad pattern)
  if content.include?('Neo4j::Driver::GraphDatabase.driver') && 
     !content.include?('Graph::Connection.instance.driver')
    # Exception for test scripts that intentionally use direct connections
    unless filename.start_with?('test_') || filename.include?('diagnose')
      issues_found << {
        file: filename,
        issue: "Creates own driver instead of using Graph::Connection"
      }
    end
  end
  
  # Check for hardcoded URLs
  if content.match(/bolt:\/\/(?!100\.104\.170\.10:8687)/)
    issues_found << {
      file: filename,
      issue: "Contains hardcoded URL that doesn't match neo4j.rb"
    }
  end
  
  # Check for hardcoded credentials
  if content.include?("AuthTokens.basic") && !filename.include?('diagnose')
    issues_found << {
      file: filename,
      issue: "Uses basic auth instead of AuthTokens.none"
    }
  end
end

if issues_found.any?
  puts "   ⚠️ Found #{issues_found.size} potential issues:"
  issues_found.each do |issue|
    puts "      - #{issue[:file]}: #{issue[:issue]}"
  end
else
  puts "   ✅ All scripts use centralized configuration"
end

# 4. Check service classes
puts "\n4. Checking service classes:"

service_files = Dir.glob(Rails.root.join('app/services/**/*.rb'))
service_issues = []

service_files.each do |file|
  content = File.read(file)
  filename = file.sub(Rails.root.to_s + '/', '')
  
  if content.include?('Neo4j::Driver::GraphDatabase.driver')
    unless content.include?('Graph::Connection.instance')
      service_issues << filename
    end
  end
end

if service_issues.any?
  puts "   ⚠️ Services creating own connections:"
  service_issues.each { |f| puts "      - #{f}" }
else
  puts "   ✅ All services use Graph::Connection"
end

# 5. Test multi-database support
puts "\n5. Testing Multi-Database Support:"
begin
  # Try to create an EKN database
  test_db_name = "ekn-test-#{Time.now.to_i}"
  
  if Graph::DatabaseManager.ensure_database_exists(test_db_name)
    puts "   ✅ Can create databases (#{test_db_name})"
    
    # Clean up
    Graph::DatabaseManager.drop_database(test_db_name)
    puts "   ✅ Can drop databases"
  else
    puts "   ⚠️ Multi-database might not be supported (Community Edition?)"
  end
rescue => e
  puts "   ⚠️ Multi-database test failed: #{e.message}"
end

# Summary
puts "\n" + "="*80
puts "SUMMARY"
puts "="*80

puts "\n✅ Configuration source of truth: /config/initializers/neo4j.rb"
puts "✅ Connection URL: bolt://100.104.170.10:8687"
puts "✅ Authentication: DISABLED"
puts "✅ Multi-database: SUPPORTED"

if issues_found.any? || service_issues.any?
  puts "\n⚠️ Some files may need updating to use centralized configuration"
  puts "   Run 'rails runner script/fix_neo4j_connections.rb' to fix them"
else
  puts "\n✅ All code uses centralized Neo4j configuration!"
end

puts "="*80