#!/usr/bin/env ruby

# Check if Arctic Research data still exists in Neo4j
begin
  driver = Graph::Connection.instance.driver
  
  # Try the database that should exist  
  databases_to_check = ["ekn-arctic-research", "arctic-research"]
  
  databases_to_check.each do |db_name|
    begin
      puts "Checking database: #{db_name}"
      session = driver.session(database: db_name)
      result = session.run("MATCH (n) RETURN count(n) as count LIMIT 1")
      count = result.first["count"]
      puts "  ✅ Found #{count} nodes in #{db_name}"
      session.close
      
      # Check what pools exist
      session = driver.session(database: db_name)  
      result = session.run("MATCH (n) RETURN DISTINCT labels(n)[0] as label, count(n) as count ORDER BY count DESC")
      puts "  Pools in #{db_name}:"
      result.each do |record| 
        puts "    #{record['label']}: #{record['count']}" 
      end
      session.close
      
    rescue => e
      puts "  ❌ Database #{db_name} not accessible: #{e.message}"
    end
  end
  
rescue => e
  puts "❌ Error checking Neo4j: #{e.message}"
end