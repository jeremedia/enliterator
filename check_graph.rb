#!/usr/bin/env ruby

batch = IngestBatch.find(76)
ekn = batch.ekn
driver = Graph::Connection.instance.driver

puts "Checking database: #{ekn.neo4j_database_name}"

driver.session(database: ekn.neo4j_database_name) do |session|
  session.read_transaction do |tx|
    # Count nodes
    nodes_result = tx.run("MATCH (n) RETURN count(n) as count").to_a.first
    
    # Count relationships (excluding HAS_RIGHTS)
    rels_result = tx.run("MATCH ()-[r]->() WHERE type(r) <> 'HAS_RIGHTS' RETURN count(r) as count").to_a.first
    
    # Get relationship types
    types_result = tx.run("MATCH ()-[r]->() WHERE type(r) <> 'HAS_RIGHTS' RETURN DISTINCT type(r) as type, count(r) as count").to_a
    
    puts "\n=== Graph Statistics ==="
    puts "Nodes: #{nodes_result['count']}"
    puts "Relationships: #{rels_result['count']}"
    puts "Density: #{'%.4f' % (rels_result['count'].to_f / nodes_result['count'].to_f)}"
    
    puts "\n=== Relationship Types ==="
    types_result.each do |row|
      puts "  #{row['type']}: #{row['count']}"
    end
  end
end