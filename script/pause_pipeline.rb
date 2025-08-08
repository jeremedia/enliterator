#!/usr/bin/env ruby

run_id = ARGV[0]&.to_i || 25

run = EknPipelineRun.find(run_id)
puts "Pipeline Run ##{run.id}:"
puts "  Current Status: #{run.status}"
puts "  Current Stage: #{run.current_stage}"

if run.running?
  run.update!(status: 'paused')
  puts "✅ Successfully paused run ##{run.id}"
elsif run.status == 'paused'
  puts "⏸️ Run ##{run.id} is already paused"
else
  puts "⚠️ Run ##{run.id} is #{run.status}, cannot pause"
end