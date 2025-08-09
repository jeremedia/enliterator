#!/usr/bin/env ruby

batch = IngestBatch.find(76)
ekn = batch.ekn
driver = Graph::Connection.instance.driver

puts "Checking database: #{ekn.neo4j_database_name}"

driver.session(database: ekn.neo4j_database_name) do |session|
  session.read_transaction do |tx|
    # Sample a few nodes of each type to see their properties
    ['Idea', 'Practical', 'Experience'].each do |pool|
      puts "\n=== #{pool} Nodes (sample) ==="
      result = tx.run("MATCH (n:#{pool}) RETURN n LIMIT 3").to_a
      
      if result.empty?
        puts "  No #{pool} nodes found"
      else
        result.each_with_index do |row, i|
          node = row['n']
          puts "  Node #{i+1}:"
          node.properties.each do |key, value|
            # Truncate long values for readability
            display_value = value.to_s.length > 100 ? "#{value.to_s[0..97]}..." : value
            puts "    #{key}: #{display_value}"
          end
        end
      end
    end
    
    # Check if nodes have 'label' property
    puts "\n=== Nodes with 'label' property ==="
    result = tx.run("MATCH (n) WHERE n.label IS NOT NULL RETURN labels(n)[0] as type, count(n) as count").to_a
    if result.empty?
      puts "  No nodes have 'label' property"
    else
      result.each do |row|
        puts "  #{row['type']}: #{row['count']} nodes"
      end
    end
    
    # Check what properties are most common
    puts "\n=== Common Properties Across All Nodes ==="
    result = tx.run("MATCH (n) UNWIND keys(n) as key RETURN DISTINCT key ORDER BY key").to_a
    properties = result.map { |r| r['key'] }
    puts "  Properties found: #{properties.join(', ')}"
  end
end