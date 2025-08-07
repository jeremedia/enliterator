#!/usr/bin/env ruby

puts '=== CHECKING CREATED ENTITIES FOR BATCH 30 ==='
batch = IngestBatch.find(30)

# Check entities created around batch time
created_after = batch.created_at
puts "Looking for entities created after: #{created_after}"

%w[Idea Manifest Experience Relational Evolutionary Practical Emanation].each do |pool|
  recent_count = pool.constantize.where('created_at >= ?', created_after).count
  total_count = pool.constantize.count
  puts "#{pool}: #{recent_count} recent / #{total_count} total"
  
  # Show recent items
  if recent_count > 0
    pool.constantize.where('created_at >= ?', created_after).limit(3).each do |item|
      puts "  - #{item.canonical_name} (#{item.created_at})"
    end
  end
end

puts "\n=== CHECKING PIPELINE RUN STAGE ==="
run = EknPipelineRun.find(7)
puts "Current stage: #{run.current_stage} (#{run.current_stage_number})"
puts "Status: #{run.status}"

puts "\n=== CHECKING NEO4J NODES ==="
begin
  driver = Neo4j::Driver::GraphDatabase.driver(ENV['NEO4J_URL'], Neo4j::Driver::AuthTokens.basic('neo4j', 'cheese28'))
  session = driver.session
  result = session.run('MATCH (n) RETURN count(n) as total')
  total_nodes = result.single.first
  puts "Total nodes in Neo4j: #{total_nodes}"
  session.close
  driver.close
rescue => e
  puts "Neo4j error: #{e.message}"
end