#!/usr/bin/env ruby
# frozen_string_literal: true

# Test script to verify automatic pipeline execution with Solid Queue
# Run with: rails runner script/test_automatic_pipeline.rb

require 'rainbow'

puts "\n" + "="*80
puts Rainbow("🧪 Testing Automatic Pipeline Execution").cyan
puts "="*80 + "\n"

# Check if Solid Queue is running
solid_queue_running = `ps aux | grep solid_queue | grep -v grep`.strip.length > 0

if !solid_queue_running
  puts Rainbow("❌ Solid Queue is not running!").red
  puts "\nPlease start it with one of these methods:"
  puts "  1. Run all services: " + Rainbow("bin/dev").yellow
  puts "  2. Run worker only: " + Rainbow("bundle exec rails solid_queue:start").yellow
  puts "\nThen run this test again."
  exit 1
end

puts Rainbow("✅ Solid Queue is running").green

# Create a small test EKN and batch
puts "\n" + Rainbow("Creating test EKN and batch...").yellow

test_ekn = Ekn.create!(
  name: "Pipeline Test #{Time.now.to_i}",
  description: "Testing automatic pipeline execution",
  status: 'active',
  domain_type: 'test'
)

# Create a few test files
test_dir = Rails.root.join('tmp', 'pipeline_test')
FileUtils.mkdir_p(test_dir)

test_files = []
3.times do |i|
  file_path = test_dir.join("test_#{i}.txt")
  File.write(file_path, "Test content #{i}\nThis tests automatic pipeline execution.")
  test_files << file_path.to_s
end

puts "Created #{test_files.count} test files"

# Start the pipeline with auto_advance enabled
puts "\n" + Rainbow("Starting pipeline with auto_advance=true...").yellow

pipeline_run = Pipeline::Orchestrator.process_ekn(
  test_ekn,
  test_files,
  batch_name: "Auto Test Batch",
  auto_advance: true  # This should make stages chain automatically
)

puts Rainbow("✅ Pipeline started: Run ##{pipeline_run.id}").green
puts "Initial status: #{pipeline_run.status}"
puts "Auto-advance: #{pipeline_run.auto_advance}"

# Monitor for 30 seconds to see if stages advance automatically
puts "\n" + Rainbow("Monitoring pipeline for 30 seconds...").yellow
puts "(Stages should advance automatically if working correctly)\n"

start_time = Time.current
timeout = 30.seconds
last_stage = nil

while (Time.current - start_time) < timeout
  pipeline_run.reload
  current_stage = "#{pipeline_run.current_stage_number}/9 - #{pipeline_run.current_stage}"
  
  if current_stage != last_stage
    puts Rainbow("[#{(Time.current - start_time).round(1)}s]").cyan + " Stage changed to: " + Rainbow(current_stage).yellow
    last_stage = current_stage
  end
  
  if pipeline_run.completed?
    puts Rainbow("\n🎉 Pipeline completed automatically!").green
    break
  elsif pipeline_run.failed?
    puts Rainbow("\n❌ Pipeline failed at stage: #{pipeline_run.current_stage}").red
    break
  end
  
  sleep 1
end

# Final status
puts "\n" + "="*80
puts Rainbow("Final Status:").cyan
puts "="*80

pipeline_run.reload
status = pipeline_run.detailed_status

puts "Pipeline ID: ##{status[:id]}"
puts "Status: #{Rainbow(status[:status]).send(status[:status] == 'completed' ? :green : :yellow)}"
puts "Progress: #{status[:progress_percentage]}%"
puts "Current Stage: #{status[:current_stage]}"
puts "Duration: #{status[:duration_seconds]}s"
puts "Stages Completed: #{status[:stages_completed].join(', ')}" if status[:stages_completed].any?

# Check if it's actually advancing
if pipeline_run.current_stage_number > 1
  puts Rainbow("\n✅ SUCCESS: Pipeline is advancing automatically!").green
  puts "The pipeline has progressed beyond Stage 1, confirming automatic execution."
else
  puts Rainbow("\n⚠️  WARNING: Pipeline may not be advancing automatically").yellow
  puts "After 30 seconds, still at Stage #{pipeline_run.current_stage_number}"
  puts "\nPossible issues:"
  puts "  - Jobs may be queued but not processing"
  puts "  - Stage implementations may have errors"
  puts "  - Check: " + Rainbow("tail -f log/development.log").cyan
end

# Cleanup
puts "\n🧹 Cleaning up test data..."
pipeline_run.pause! if pipeline_run.running?
test_ekn.destroy!
FileUtils.rm_rf(test_dir)

puts Rainbow("✅ Test complete!").green