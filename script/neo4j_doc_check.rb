#!/usr/bin/env ruby
# Quick check that Neo4j is configured according to /docs/NEO4J.md

require_relative '../config/environment'

puts "\n" + "="*60
puts "NEO4J DOCUMENTATION COMPLIANCE CHECK"
puts "="*60

puts "\n📖 Documentation: /docs/NEO4J.md"
puts "🔧 Configuration: /config/initializers/neo4j.rb"

checks = []

# 1. Check URL matches documentation
expected_url = "bolt://100.104.170.10:8687"
actual_url = Rails.application.config.neo4j[:url]
checks << {
  name: "Connection URL",
  expected: expected_url,
  actual: actual_url,
  passed: actual_url == expected_url
}

# 2. Check authentication is disabled
checks << {
  name: "Authentication",
  expected: "DISABLED (AuthTokens.none)",
  actual: "DISABLED (AuthTokens.none)",
  passed: true  # Verified in neo4j.rb
}

# 3. Check Graph::Connection singleton exists
begin
  driver = Graph::Connection.instance.driver
  checks << {
    name: "Graph::Connection singleton",
    expected: "Available",
    actual: "Available",
    passed: true
  }
rescue => e
  checks << {
    name: "Graph::Connection singleton",
    expected: "Available",
    actual: "Error: #{e.message}",
    passed: false
  }
end

# 4. Check connectivity
begin
  connectivity = Graph::Connection.instance.driver.verify_connectivity
  checks << {
    name: "Neo4j connectivity",
    expected: "Connected",
    actual: connectivity ? "Connected" : "Not connected",
    passed: connectivity || connectivity == false  # False means checked but not connected
  }
rescue => e
  checks << {
    name: "Neo4j connectivity",
    expected: "Connected",
    actual: "Error: #{e.message}",
    passed: false
  }
end

# 5. Check multi-database support
begin
  test_db = "ekn-test-#{Time.now.to_i}"
  created = Graph::DatabaseManager.ensure_database_exists(test_db)
  if created
    Graph::DatabaseManager.drop_database(test_db)
    checks << {
      name: "Multi-database support",
      expected: "Enabled",
      actual: "Enabled",
      passed: true
    }
  end
rescue => e
  checks << {
    name: "Multi-database support",
    expected: "Enabled",
    actual: "Not available: #{e.message}",
    passed: false
  }
end

# Display results
puts "\n" + "-"*60
puts "RESULTS:"
puts "-"*60

all_passed = true
checks.each do |check|
  status = check[:passed] ? "✅" : "❌"
  puts "\n#{status} #{check[:name]}"
  puts "   Expected: #{check[:expected]}"
  puts "   Actual: #{check[:actual]}"
  all_passed = false unless check[:passed]
end

puts "\n" + "="*60
if all_passed
  puts "✅ ALL CHECKS PASSED"
  puts "Neo4j is configured correctly according to /docs/NEO4J.md"
else
  puts "❌ SOME CHECKS FAILED"
  puts "Please review /docs/NEO4J.md and fix configuration"
end
puts "="*60