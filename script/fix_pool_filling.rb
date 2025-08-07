#!/usr/bin/env ruby

puts '=== FIXING STAGE 4 - POOL FILLING ==='
batch = IngestBatch.find(30)
run = EknPipelineRun.find(7)

puts "Current batch status: #{batch.status}"
puts "Current run stage: #{run.current_stage}"

puts "\n=== RUNNING POOL FILLING SERVICE ==="
begin
  service = Pools::FillingService.new(batch)
  result = service.call
  puts "Pool filling result: #{result}"
  
  # Check results
  items = IngestItem.where(ingest_batch: batch)
  puts "\nAfter pool filling:"
  items.group(:pool_status).count.each { |status, count| puts "  #{status}: #{count}" }
  
  completed_items = items.where(pool_status: 'completed')
  puts "\nCompleted pool items by type:"
  completed_items.group(:pool_item_type).count.each { |type, count| puts "  #{type}: #{count}" }
  
  if completed_items.any?
    puts "\n✅ Pool filling successful - proceeding to graph assembly"
    run.update!(current_stage: 'graph', current_stage_number: 5)
  else
    puts "\n❌ Pool filling failed - no completed items"
  end
  
rescue => e
  puts "ERROR in pool filling: #{e.message}"
  puts e.backtrace.first(5).join("\n")
end