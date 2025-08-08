#!/usr/bin/env ruby

pipeline_id = ARGV[0] || EknPipelineRun.last.id
pr = EknPipelineRun.find(pipeline_id)
batch = pr.ingest_batch

puts "="*60
puts "PIPELINE RUN ##{pr.id} STATUS"
puts "="*60
puts "Status: #{pr.status}"
puts "Current stage: #{pr.current_stage} (Stage #{pr.current_stage_number})"
puts "Started: #{pr.created_at}"
puts "Running for: #{((Time.current - pr.created_at) / 60).round(1)} minutes"

puts "\nStage Progress:"
puts "-"*40
pr.stage_statuses.each do |stage, status|
  next if status == 'pending'
  marker = status == 'completed' ? '✅' : (status == 'running' ? '🏃' : '❌')
  puts "#{marker} Stage #{stage}: #{status}"
end

# Current stage details
case pr.current_stage
when 'pools'
  extracted = batch.ingest_items.where(pool_status: 'extracted').count
  pending = batch.ingest_items.where(pool_status: 'pending').count
  total = extracted + pending
  puts "\nStage 4 (Pools) Progress:"
  puts "  Extracted: #{extracted}/#{total} items"
  if pending > 0
    puts "  Remaining: #{pending} items"
  end
when 'graph'
  puts "\nStage 5 (Graph) Progress:"
  # Add graph metrics when we get there
when 'embedding'
  puts "\nStage 6 (Embedding) Progress:"
  # Add embedding metrics when we get there
end

# Error information
if pr.failed?
  puts "\n❌ PIPELINE FAILED"
  puts "Error: #{pr.error_message}"
end

# Summary stats
puts "\n" + "="*60
puts "SUMMARY"
puts "="*60
puts "Total items: #{batch.ingest_items.count}"
puts "Lexicon entries created: #{LexiconAndOntology.count}"
puts "Items sent to pools: #{batch.ingest_items.where(pool_status: ['pending', 'extracted']).count}"
puts "Items with pools extracted: #{batch.ingest_items.where(pool_status: 'extracted').count}"