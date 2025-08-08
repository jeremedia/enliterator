#!/usr/bin/env ruby

# Cancel stuck pipeline runs
[26, 27].each do |run_id|
  begin
    run = EknPipelineRun.find(run_id)
    puts "Cancelling run ##{run.id}..."
    run.cancel!
    puts "  ✅ Cancelled successfully"
  rescue => e
    puts "  ❌ Error: #{e.message}"
  end
end

puts "\nCurrent pipeline runs:"
EknPipelineRun.order(id: :desc).limit(5).each do |run|
  puts "  ##{run.id}: #{run.status} at stage #{run.current_stage}"
end