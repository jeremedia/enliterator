#!/usr/bin/env ruby
# Script to properly cancel a specific pipeline run using the AASM event

run_id = ARGV[0]&.to_i || 25

begin
  run = EknPipelineRun.find(run_id)
  puts "Cancelling Pipeline Run ##{run_id}..."
  puts "Current status: #{run.status}"
  
  # Use the AASM cancel event which properly handles jobs and notifications
  run.cancel!
  
  puts "✅ Pipeline ##{run_id} cancelled successfully"
  puts "  New status: #{run.status}"
  
rescue ActiveRecord::RecordNotFound
  puts "❌ Pipeline run ##{run_id} not found"
rescue AASM::InvalidTransition => e
  puts "❌ Cannot cancel from status '#{run.status}'. Valid statuses for cancellation: running, paused, retrying, initialized"
  puts "  Error: #{e.message}"
rescue => e
  puts "❌ Error: #{e.message}"
  puts e.backtrace.first(5)
end