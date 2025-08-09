#!/usr/bin/env ruby

# Check last pipeline run
run = EknPipelineRun.find(58)
batch = run.ingest_batch

puts "=== Pipeline Run ##{run.id} ==="
puts "Status: #{run.status}"
puts "Current Stage: #{run.current_stage}"
puts "Batch: #{batch.name} (ID: #{batch.id})"

# Check stage metrics
if run.stage_metrics && run.stage_metrics['relationships']
  rel_metrics = run.stage_metrics['relationships']
  puts "\n=== Relationship Discovery Metrics ==="
  puts "Entities processed: #{rel_metrics['entities_processed']}"
  puts "Clusters analyzed: #{rel_metrics['clusters_analyzed']}"
  puts "Relationships discovered: #{rel_metrics['relationships_discovered']}"
  puts "Relationships created: #{rel_metrics['relationships_created']}"
  puts "Errors: #{rel_metrics['errors']}"
end

# Check for failed jobs
puts "\n=== Recent Failed Jobs ==="
SolidQueue::FailedExecution.order(created_at: :desc).first(3).each do |f|
  job = f.job
  puts "#{job.class_name}: #{f.error['message'] if f.error}"
end

# Check actual entities in PostgreSQL
puts "\n=== PostgreSQL Entity Counts ==="
['idea', 'practical', 'experience'].each do |pool|
  count = batch.pool_extractions.where(pool_type: pool).count
  puts "#{pool.capitalize}: #{count}"
end
total = batch.pool_extractions.count
puts "Total: #{total}"