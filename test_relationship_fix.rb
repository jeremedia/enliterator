#!/usr/bin/env ruby

puts "=== Testing Relationship Discovery Fix ==="

# Create a new pipeline run for testing
batch = IngestBatch.find(76)
ekn = batch.ekn
run = EknPipelineRun.create!(
  status: "running",
  current_stage: "relationships",
  current_stage_number: 6,
  stage_statuses: {"relationships" => "running"},
  ingest_batch: batch,
  ekn: ekn
)

puts "Created pipeline run ##{run.id}"
puts "Starting relationship discovery job..."

# Run the job
begin
  Graph::RelationshipDiscoveryJob.perform_now(run.id)
  
  # Check results
  run.reload
  if run.stage_metrics && run.stage_metrics['relationships']
    metrics = run.stage_metrics['relationships']
    puts "\n=== Results ==="
    puts "Entities processed: #{metrics['entities_processed']}"
    puts "Clusters analyzed: #{metrics['clusters_analyzed']}"
    puts "Relationships discovered: #{metrics['relationships_discovered']}"
    puts "Relationships created: #{metrics['relationships_created']}"
    puts "Errors: #{metrics['errors']}"
    
    if metrics['relationships_discovered'] == metrics['relationships_created']
      puts "\n✅ SUCCESS: All discovered relationships were created!"
    else
      puts "\n⚠️  PARTIAL: #{metrics['relationships_created']}/#{metrics['relationships_discovered']} relationships created"
    end
  else
    puts "No metrics found - job may have failed"
  end
  
  # Check Neo4j directly
  ekn = batch.ekn
  driver = Graph::Connection.instance.driver
  driver.session(database: ekn.neo4j_database_name) do |session|
    session.read_transaction do |tx|
      result = tx.run("MATCH ()-[r]->() WHERE type(r) <> 'HAS_RIGHTS' RETURN count(r) as count").to_a.first
      puts "\n=== Neo4j Graph State ==="
      puts "Total relationships in graph: #{result['count']}"
    end
  end
  
rescue => e
  puts "\n❌ ERROR: #{e.message}"
  puts e.backtrace.first(5).join("\n")
end