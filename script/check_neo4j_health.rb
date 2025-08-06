#!/usr/bin/env ruby
# Neo4j Health Check Script
# Run this to verify Neo4j is properly configured and has data

require_relative '../config/environment'

puts "\n" + "="*80
puts "Neo4j Health Check"
puts "="*80

begin
  driver = Graph::Connection.instance.driver
  
  # Test connection
  print "\n1. Testing connection... "
  driver.verify_connectivity
  puts "✅ Connected!"
  
  # Get node count
  print "\n2. Counting nodes... "
  session = driver.session
  result = session.run("MATCH (n) RETURN count(n) as count")
  node_count = result.single['count']
  puts "✅ #{node_count.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse} nodes"
  
  # Get node types
  print "\n3. Checking node types... "
  result = session.run("MATCH (n) RETURN DISTINCT labels(n) as labels, count(n) as count ORDER BY count DESC LIMIT 10")
  types = []
  result.each { |record| types << "#{record['labels'].first}: #{record['count']}" }
  puts "✅ Found #{types.size} types"
  types.each { |t| puts "   - #{t}" }
  
  # Check for batch_id property
  print "\n4. Checking batch_id property... "
  result = session.run("MATCH (n) WHERE n.batch_id IS NOT NULL RETURN count(n) as count")
  batch_count = result.single['count']
  if batch_count > 0
    puts "✅ #{batch_count} nodes have batch_id"
    
    # List distinct batch_ids
    result = session.run("MATCH (n) WHERE n.batch_id IS NOT NULL RETURN DISTINCT n.batch_id as id LIMIT 5")
    puts "   Sample batch_ids:"
    result.each { |record| puts "   - #{record['id']}" }
  else
    puts "⚠️  NO nodes have batch_id property"
    puts "   This means Graph::QueryService with batch_id filtering will return empty results!"
  end
  
  # Test Graph::QueryService
  print "\n5. Testing Graph::QueryService... "
  
  # With batch_id (likely to fail)
  ekn = IngestBatch.first
  if ekn
    service_with_batch = Graph::QueryService.new(ekn.id)
    results_with = service_with_batch.search_entities("", limit: 1)
    
    # Without batch_id
    service_without_batch = Graph::QueryService.new(nil)
    results_without = service_without_batch.search_entities("", limit: 1)
    
    if results_with.empty? && results_without.any?
      puts "⚠️  Warning!"
      puts "   - With batch_id filter: 0 results"
      puts "   - Without batch_id filter: #{results_without.size} results"
      puts "   → The batch_id filter is preventing data access!"
    elsif results_with.any?
      puts "✅ Both queries work"
    else
      puts "❌ Both queries return empty"
    end
  else
    puts "⚠️  No IngestBatch found to test with"
  end
  
  # Get relationship count
  print "\n6. Counting relationships... "
  result = session.run("MATCH ()-[r]->() RETURN count(r) as count")
  rel_count = result.single['count']
  puts "✅ #{rel_count.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse} relationships"
  
  # Sample data
  puts "\n7. Sample data:"
  result = session.run("MATCH (n) RETURN n LIMIT 3")
  result.each_with_index do |record, i|
    node = record['n']
    puts "   Node #{i+1}:"
    puts "     Labels: #{node.labels.join(', ')}"
    props = node.properties.to_h
    puts "     Properties: #{props.keys.first(5).join(', ')}#{ props.keys.size > 5 ? '...' : ''}"
    puts "     Name/Label: #{props[:name] || props[:label] || props[:title] || 'N/A'}"
  end
  
  session.close
  
  puts "\n" + "="*80
  puts "Summary:"
  puts "="*80
  puts "✅ Neo4j is running and accessible"
  puts "✅ Database has #{node_count.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse} nodes"
  puts "✅ Database has #{rel_count.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse} relationships"
  
  if batch_count == 0
    puts "\n⚠️  IMPORTANT: Nodes don't have batch_id properties."
    puts "   To use this data with the Knowledge Navigator:"
    puts "   - Pass nil to Graph::QueryService instead of a batch_id"
    puts "   - Or update nodes to add batch_id properties"
  end
  
  puts "="*80
  
rescue => e
  puts "❌ Error: #{e.message}"
  puts "\nTroubleshooting:"
  puts "1. Check if Neo4j is running: brew services list | grep neo4j"
  puts "2. Start Neo4j if needed: brew services start neo4j"
  puts "3. Verify credentials in config/initializers/neo4j.rb"
  puts "   - URL: bolt://127.0.0.1:7687"
  puts "   - Username: neo4j"
  puts "   - Password: cheese28"
end