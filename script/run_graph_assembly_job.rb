#!/usr/bin/env ruby

puts '=== RUNNING STAGE 5 - GRAPH ASSEMBLY JOB ==='
batch = IngestBatch.find(30)
run = EknPipelineRun.find(7)

puts "Current entities in database:"
%w[Idea Manifest Experience Relational Evolutionary Practical Emanation].each do |pool|
  count = pool.constantize.count
  puts "  #{pool}: #{count} entities"
end

puts "\n=== RUNNING GRAPH ASSEMBLY JOB ==="
begin
  job = Graph::AssemblyJob.new
  result = job.perform(batch.id)
  puts "Graph assembly completed successfully!"
  
  # Reload batch to get updated stats
  batch.reload
  puts "\nBatch status: #{batch.status}"
  puts "Assembly stats: #{batch.graph_assembly_stats}"
  
  # Check Neo4j nodes were created
  # Use centralized connection from neo4j.rb
  driver = Graph::Connection.instance.driver
  session = driver.session
  node_count = session.run('MATCH (n) RETURN count(n) as total').single.first
  puts "\nTotal nodes in Neo4j: #{node_count}"
  
  # Check node types if nodes exist
  if node_count > 0
    type_result = session.run('MATCH (n) RETURN labels(n)[0] as label, count(n) as count')
    puts "\nNode types:"
    type_result.each { |record| puts "  #{record[:label]}: #{record[:count]}" }
    
    # Update pipeline to next stage
    run.update!(current_stage: 'embeddings', current_stage_number: 6)
    puts "\n✅ Advanced pipeline to Stage 6 (Embeddings)"
  else
    puts "\n⚠️ No nodes were created in Neo4j"
  end
  
  session.close
  
rescue => e
  puts "ERROR in graph assembly: #{e.message}"
  puts e.backtrace.first(5).join("\n")
end