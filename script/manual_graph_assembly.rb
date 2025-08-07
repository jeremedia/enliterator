#!/usr/bin/env ruby

puts '=== MANUAL GRAPH ASSEMBLY - STAGE 5 ==='

begin
  # Get the batch and run
  run = EknPipelineRun.find(7)
  batch = IngestBatch.find(30)
  
  puts "Processing batch: #{batch.name} (ID: #{batch.id})"
  puts "Current batch status: #{batch.status}"
  
  # Check if we have pool items to work with
  puts "Checking pool items..."
  ten_pool_items = TenPool.where(ingest_batch: batch)
  puts "TenPool items found: #{ten_pool_items.count}"
  
  if ten_pool_items.any?
    puts "Starting Graph Assembly Service..."
    service = Graph::AssemblyService.new(batch)
    result = service.call
    
    puts "Graph assembly completed successfully!"
    puts "Result: #{result}"
    
    # Verify nodes were created
    driver = Neo4j::Driver::GraphDatabase.driver(ENV['NEO4J_URL'], Neo4j::Driver::AuthTokens.basic('neo4j', 'cheese28'))
    session = driver.session
    node_count = session.run('MATCH (n) RETURN count(n) as total').single.first
    puts "Total nodes in Neo4j after assembly: #{node_count}"
    session.close
    driver.close
    
    # Update pipeline status
    run.update!(current_stage: 'embeddings', current_stage_number: 6)
    puts "Pipeline advanced to Stage 6 (Embeddings)"
  else
    puts "ERROR: No TenPool items found for batch #{batch.id}"
    puts "Batch status: #{batch.status}"
    
    # Let's check what pool items exist
    puts "\nChecking all pool-related tables..."
    %w[Idea Manifest Experience Relational Evolutionary Practical Emanation Rights Lexicon Intent].each do |pool|
      count = pool.constantize.where(ingest_batch: batch).count
      puts "#{pool}: #{count} items"
    end
  end
  
rescue => e
  puts "ERROR in manual graph assembly: #{e.message}"
  puts e.backtrace.first(5).join("\n")
end