# frozen_string_literal: true

namespace :neo4j do
  desc "Test Neo4j connection and show configuration"
  task test_connection: :environment do
    puts "\n" + "=" * 60
    puts "Neo4j Connection Test"
    puts "=" * 60
    
    config = Rails.application.config.neo4j
    puts "\n📋 Configuration:"
    puts "  URL: #{config[:url]}"
    puts "  Pool Size: #{config[:pool_size]}"
    puts "  Timeout: #{config[:connection_timeout]}s"
    
    begin
      driver = Graph::Connection.instance.driver
      session = driver.session
      
      # Test basic connection
      result = session.run("RETURN 1 as test, datetime() as server_time")
      record = result.single
      
      if record['test'] == 1
        puts "\n✅ Connection successful!"
        puts "  Server time: #{record['server_time']}"
      end
      
      # List databases
      begin
        system_session = driver.session(database: 'system')
        db_result = system_session.run("SHOW DATABASES")
        
        puts "\n📚 Available databases:"
        db_result.each do |db|
          status = db['currentStatus'] == 'online' ? '🟢' : '🔴'
          puts "  #{status} #{db['name']} (#{db['currentStatus']})"
        end
        system_session.close
      rescue => e
        puts "\n⚠️  Could not list databases (might be Community Edition)"
      end
      
      # Check for GenAI plugin
      genai_result = session.run(<<~CYPHER)
        SHOW PROCEDURES
        YIELD name 
        WHERE name STARTS WITH 'genai.' 
        RETURN collect(name) as procedures
      CYPHER
      
      procedures = genai_result.single['procedures']
      if procedures.any?
        puts "\n✅ Neo4j GenAI plugin installed:"
        procedures.first(5).each do |proc|
          puts "  - #{proc}"
        end
        puts "  ... and #{procedures.size - 5} more" if procedures.size > 5
      else
        puts "\n⚠️  Neo4j GenAI plugin not found"
      end
      
      # Check node count
      node_result = session.run("MATCH (n) RETURN count(n) as count")
      node_count = node_result.single['count']
      puts "\n📊 Database statistics:"
      puts "  Total nodes: #{node_count}"
      
      if node_count > 0
        # Get node type distribution
        type_result = session.run(<<~CYPHER)
          MATCH (n) 
          RETURN labels(n)[0] as type, count(n) as count 
          ORDER BY count DESC 
          LIMIT 5
        CYPHER
        
        puts "  Top node types:"
        type_result.each do |record|
          puts "    - #{record['type']}: #{record['count']}"
        end
      end
      
      session.close
      puts "\n" + "=" * 60
      puts "✅ All tests passed!"
      puts "=" * 60
      
    rescue => e
      puts "\n❌ Connection failed!"
      puts "  Error: #{e.message}"
      puts "\nTroubleshooting:"
      puts "1. Check if Neo4j is running:"
      puts "   nc -zv 100.104.170.10 8687"
      puts "2. Verify .env configuration:"
      puts "   grep NEO4J_URL .env"
      puts "3. Test with a script:"
      puts "   ruby script/test_no_auth.rb"
      
      exit 1
    end
  end
  
  desc "Create an isolated EKN database"
  task :create_ekn, [:name] => :environment do |t, args|
    name = args[:name] || "test-ekn"
    
    puts "Creating EKN database: #{name}"
    
    ekn = EknManager.create_ekn(
      name: name,
      description: "Test EKN created via rake task"
    )
    
    puts "✅ Created EKN ##{ekn.id}"
    puts "  Neo4j database: #{ekn.neo4j_database_name}"
    puts "  PostgreSQL schema: #{ekn.postgres_schema_name}"
    puts "  Storage path: #{ekn.storage_root_path}"
  end
end