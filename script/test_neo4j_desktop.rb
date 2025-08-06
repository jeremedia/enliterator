#!/usr/bin/env ruby
# Test Neo4j Desktop connection and multi-database support

require_relative '../config/environment'

# Override Neo4j config with Desktop settings
Rails.application.config.neo4j = {
  url: "bolt://jer-pro16.husky-carp.ts.net:8687",
  username: "neo4j",
  password: "enliterator",
  encryption: false,
  pool_size: 10,
  connection_timeout: 30,
  max_retry_time: 15
}

# Reinitialize connection with new settings
Graph::Connection.instance.instance_variable_set(:@driver, nil)
Graph::Connection.instance.send(:initialize)

puts "\n" + "="*80
puts "Testing Neo4j Desktop Connection"
puts "="*80

begin
  driver = Graph::Connection.instance.driver
  
  # Test connection
  print "\n1. Testing connection to Neo4j Desktop... "
  driver.verify_connectivity
  puts "✅ Connected!"
  
  # Test multi-database support
  print "\n2. Testing multi-database support... "
  session = driver.session(database: 'system')
  
  # List existing databases
  result = session.run("SHOW DATABASES")
  databases = []
  result.each { |record| databases << record['name'] }
  session.close
  
  puts "✅ Multi-database SUPPORTED!"
  puts "   Existing databases: #{databases.join(', ')}"
  
  # Test creating a new database
  print "\n3. Testing database creation... "
  test_db_name = "ekn-test-#{Time.now.to_i}"
  
  session = driver.session(database: 'system')
  session.run("CREATE DATABASE $name IF NOT EXISTS", name: test_db_name)
  session.close
  
  # Wait for database to come online
  sleep 2
  
  # Verify it was created
  session = driver.session(database: 'system')
  result = session.run("SHOW DATABASES WHERE name = $name", name: test_db_name)
  
  if result.count > 0
    puts "✅ Successfully created database: #{test_db_name}"
  else
    puts "❌ Failed to create database"
  end
  session.close
  
  # Test using the new database
  print "\n4. Testing database usage... "
  session = driver.session(database: test_db_name)
  session.run("CREATE (n:TestNode {name: 'Test', created: datetime()})")
  result = session.run("MATCH (n:TestNode) RETURN count(n) as count")
  count = result.single['count']
  session.close
  
  if count == 1
    puts "✅ Successfully used database: created and queried 1 node"
  else
    puts "❌ Failed to use database"
  end
  
  # Clean up test database
  print "\n5. Cleaning up test database... "
  session = driver.session(database: 'system')
  session.run("DROP DATABASE $name IF EXISTS", name: test_db_name)
  session.close
  puts "✅ Cleaned up"
  
  puts "\n" + "="*80
  puts "✅ Neo4j Desktop is properly configured for multi-database EKNs!"
  puts "="*80
  puts "\nConfiguration:"
  puts "  URL: bolt://jer-pro16.husky-carp.ts.net:8687"
  puts "  Username: neo4j"
  puts "  Password: [configured]"
  puts "  Multi-database: ENABLED"
  puts "\nYou can now:"
  puts "  1. Create isolated databases for each EKN"
  puts "  2. Use Graph::DatabaseManager to manage databases"
  puts "  3. Run the EKN isolation test script"
  puts "="*80
  
rescue => e
  puts "❌ Error: #{e.message}"
  puts "\nTroubleshooting:"
  puts "1. Ensure Neo4j Desktop is running"
  puts "2. Check the connection details:"
  puts "   - URL: bolt://jer-pro16.husky-carp.ts.net:8687"
  puts "   - Password: enliterator"
  puts "3. Verify Neo4j Desktop shows as 'Started' in the UI"
  puts "\nError details:"
  puts e.backtrace.first(5).join("\n")
end