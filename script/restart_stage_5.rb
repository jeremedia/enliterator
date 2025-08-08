#!/usr/bin/env ruby

# Script to restart Stage 5 (Graph Assembly) for a failed pipeline

pipeline_id = ARGV[0] || 41
pr = EknPipelineRun.find(pipeline_id)

puts "Restarting Stage 5 for Pipeline ##{pr.id}"
puts "Current status: #{pr.status}"
puts "Current stage: #{pr.current_stage}"

if pr.current_stage != 'graph'
  puts "ERROR: Pipeline is not at Stage 5 (graph). Current stage: #{pr.current_stage}"
  exit 1
end

# Reset pipeline to running state
pr.update!(
  status: 'running',
  error_message: nil
)

puts "Reset pipeline status to 'running'"

# Queue the Graph Assembly job
job = Graph::AssemblyJob.perform_later(pr.id)
puts "Queued Graph::AssemblyJob"

# Check if job was queued
sleep 1
queued_job = SolidQueue::Job.where(class_name: 'Graph::AssemblyJob').order(created_at: :desc).first
if queued_job && queued_job.created_at > 5.seconds.ago
  puts "✅ Job successfully queued at #{queued_job.created_at}"
  puts "Job ID: #{queued_job.id}"
else
  puts "⚠️ Could not verify job was queued"
end

puts "\nPipeline ##{pr.id} Stage 5 restart initiated"
puts "Monitor with: rails runner script/check_pipeline_status.rb #{pr.id}"