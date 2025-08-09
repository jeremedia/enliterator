#!/usr/bin/env ruby

batch = IngestBatch.find(76)
ekn = batch.ekn
driver = Graph::Connection.instance.driver

puts "=== Analyzing Relationships in #{ekn.neo4j_database_name} ==="

driver.session(database: ekn.neo4j_database_name) do |session|
  session.read_transaction do |tx|
    # Count relationships by type
    query1 = "MATCH ()-[r]->() WHERE type(r) <> 'HAS_RIGHTS' RETURN type(r) as rel_type, count(r) as count ORDER BY count DESC"
    result = tx.run(query1).to_a
    
    puts "\n=== Relationship Types ==="
    result.each do |row|
      puts "#{row['rel_type']}: #{row['count']} relationships"
    end
    
    # Sample relationships
    query2 = "MATCH (source)-[r]->(target) WHERE type(r) <> 'HAS_RIGHTS' RETURN labels(source)[0] as src, type(r) as rel, labels(target)[0] as tgt, r.confidence as conf LIMIT 10"
    result = tx.run(query2).to_a
    
    puts "\n=== Sample Relationships ==="
    result.each_with_index do |row, i|
      puts "#{i+1}. #{row['src']} -[#{row['rel']}]-> #{row['tgt']} (conf: #{row['conf']})"
    end
    
    # Check verbs
    query3 = "MATCH ()-[r]->() WHERE type(r) <> 'HAS_RIGHTS' RETURN DISTINCT type(r) as verb"
    result = tx.run(query3).to_a
    
    puts "\n=== Distinct Verbs Used ==="
    result.each do |row|
      puts "  - #{row['verb']}"
    end
  end
end

# Check RelationExtractionService to understand why only generic verbs
puts "\n=== Checking Verb Glossary ==="
puts "Available verbs in VERB_GLOSSARY:"
Graph::EdgeLoader::VERB_GLOSSARY.each do |verb, config|
  puts "  #{verb}: #{config[:source_pools].join(',')} -> #{config[:target_pools].join(',')}"
end