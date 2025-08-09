#!/usr/bin/env ruby

puts "=== Testing Improved Relationship Discovery ==="

# Clear existing relationships to start fresh
batch = IngestBatch.find(76)
ekn = batch.ekn

driver = Graph::Connection.instance.driver
driver.session(database: ekn.neo4j_database_name) do |session|
  session.write_transaction do |tx|
    # Remove all non-HAS_RIGHTS relationships
    tx.run("MATCH ()-[r]->() WHERE type(r) <> 'HAS_RIGHTS' DELETE r")
  end
end

puts "Cleared existing relationships"

# Create new pipeline run
run = EknPipelineRun.create!(
  status: "running",
  current_stage: "relationships",
  current_stage_number: 5.5,
  stage_statuses: {"relationships" => "running"},
  ingest_batch: batch,
  ekn: ekn
)

puts "Created pipeline run ##{run.id}"
puts "Running improved relationship discovery..."

# Run the job
begin
  Graph::RelationshipDiscoveryJob.perform_now(run.id)
  
  # Check results
  run.reload
  if run.stage_metrics && run.stage_metrics['relationships']
    metrics = run.stage_metrics['relationships']
    puts "\n=== Discovery Results ==="
    puts "Clusters analyzed: #{metrics['clusters_analyzed']}"
    puts "Relationships discovered: #{metrics['relationships_discovered']}"
    puts "Relationships created: #{metrics['relationships_created']}"
    puts "Tokens used: #{metrics['tokens_used']}"
  end
  
  # Check graph state
  driver.session(database: ekn.neo4j_database_name) do |session|
    session.read_transaction do |tx|
      # Count relationships
      rel_result = tx.run("MATCH ()-[r]->() WHERE type(r) <> 'HAS_RIGHTS' RETURN count(r) as count").to_a.first
      
      # Count nodes
      node_result = tx.run("MATCH (n) RETURN count(n) as count").to_a.first
      
      # Get relationship types
      types_result = tx.run("MATCH ()-[r]->() WHERE type(r) <> 'HAS_RIGHTS' RETURN DISTINCT type(r) as type, count(r) as count").to_a
      
      puts "\n=== Graph State ==="
      puts "Total nodes: #{node_result['count']}"
      puts "Total relationships: #{rel_result['count']}"
      puts "Graph density: #{'%.4f' % (rel_result['count'].to_f / node_result['count'].to_f)}"
      
      puts "\nRelationship types:"
      types_result.each do |row|
        puts "  #{row['type']}: #{row['count']}"
      end
    end
  end
  
rescue => e
  puts "\n❌ ERROR: #{e.message}"
  puts e.backtrace.first(5).join("\n")
end