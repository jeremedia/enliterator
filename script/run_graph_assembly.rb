#!/usr/bin/env ruby

puts '=== RUNNING STAGE 5 - GRAPH ASSEMBLY ==='
batch = IngestBatch.find(30)
run = EknPipelineRun.find(7)

puts "Current entities in database:"
%w[Idea Manifest Experience Relational Evolutionary Practical Emanation].each do |pool|
  count = pool.constantize.count
  puts "  #{pool}: #{count} entities"
end

puts "\n=== RUNNING GRAPH ASSEMBLY SERVICE ==="
begin
  service = Graph::AssemblyService.new(batch)
  result = service.call
  puts "Graph assembly completed successfully!"
  
  # Check Neo4j nodes were created
  driver = Neo4j::Driver::GraphDatabase.driver(ENV['NEO4J_URL'], Neo4j::Driver::AuthTokens.basic('neo4j', 'cheese28'))
  session = driver.session
  node_count = session.run('MATCH (n) RETURN count(n) as total').single.first
  puts "Total nodes in Neo4j: #{node_count}"
  
  # Check node types
  type_result = session.run('MATCH (n) RETURN labels(n)[0] as label, count(n) as count')
  puts "\nNode types:"
  type_result.each { |record| puts "  #{record[:label]}: #{record[:count]}" }
  
  session.close
  driver.close
  
  if node_count > 0
    # Update pipeline
    run.update!(current_stage: 'embeddings', current_stage_number: 6)
    batch.update!(status: 'graph_assembly_completed')
    puts "\n✅ Advanced pipeline to Stage 6 (Embeddings)"
  end
  
rescue => e
  puts "ERROR in graph assembly: #{e.message}"
  puts e.backtrace.first(5).join("\n")
end