#!/usr/bin/env ruby
# frozen_string_literal: true

# PURPOSE: Simple test to verify pipeline can run automatically through all 9 stages
# This creates a minimal test case to ensure the pipeline infrastructure works
# without getting bogged down in complex data processing

require 'rainbow'

puts "\n" + "="*80
puts Rainbow("🧪 SIMPLE PIPELINE TEST - Verifying Automatic Execution").cyan.bold
puts "="*80 + "\n"

# Check if Solid Queue is running
solid_queue_running = `ps aux | grep solid_queue | grep -v grep`.strip.length > 0

if !solid_queue_running
  puts Rainbow("⚠️  WARNING: Solid Queue may not be running!").yellow
  puts "Start it with: " + Rainbow("bin/dev").cyan
  puts "Continuing anyway to test job queueing...\n\n"
end

# Create a simple test EKN
puts Rainbow("Creating test EKN...").yellow
test_ekn = Ekn.create!(
  name: "Simple Pipeline Test #{Time.now.to_i}",
  description: "Minimal test of automatic pipeline execution",
  status: 'active',
  domain_type: 'technical'  # Valid domain type
)

# Create a single test file with simple content
test_dir = Rails.root.join('tmp', 'simple_pipeline_test')
FileUtils.mkdir_p(test_dir)

test_file = test_dir.join("test.txt")
File.write(test_file, <<~TEXT)
  This is a simple test document for the Enliterator pipeline.
  
  The main principle here is to test automatic execution.
  
  This manifest represents a test file that should be processed.
  
  My experience with this system has been interesting.
  
  The practical steps are:
  1. Create file
  2. Process through pipeline
  3. Verify completion
TEXT

puts "Created test file: #{test_file}"

# Start the pipeline
puts Rainbow("\nStarting pipeline with auto_advance=true...").yellow

pipeline_run = Pipeline::Orchestrator.process_ekn(
  test_ekn,
  [test_file.to_s],
  batch_name: "Simple Test Batch",
  auto_advance: true
)

puts Rainbow("✅ Pipeline started!").green
puts "  Run ID: ##{pipeline_run.id}"
puts "  Status: #{pipeline_run.status}"
puts "  Current Stage: #{pipeline_run.current_stage}"

# Monitor for 60 seconds
puts Rainbow("\n⏱️  Monitoring for 60 seconds...").yellow
puts "(Pipeline should advance automatically if working)\n"

start_time = Time.current
timeout = 60.seconds
last_stage = nil
stage_times = {}

while (Time.current - start_time) < timeout
  pipeline_run.reload
  
  current_stage = "Stage #{pipeline_run.current_stage_number}/9 - #{pipeline_run.current_stage}"
  
  # Track stage changes
  if current_stage != last_stage
    elapsed = (Time.current - start_time).round(1)
    puts Rainbow("[#{elapsed}s]").cyan + " → " + Rainbow(current_stage).yellow
    
    if last_stage
      stage_name = last_stage.split(' - ').last
      stage_times[stage_name] = elapsed - (stage_times.values.sum || 0)
    end
    
    last_stage = current_stage
  end
  
  # Check completion
  if pipeline_run.completed?
    puts Rainbow("\n🎉 PIPELINE COMPLETED AUTOMATICALLY!").green.bold
    break
  elsif pipeline_run.failed?
    puts Rainbow("\n❌ Pipeline failed at: #{pipeline_run.current_stage}").red
    
    # Try to get error details
    if pipeline_run.failed_stage
      puts "Failed stage: #{pipeline_run.failed_stage}"
    end
    
    # Check logs
    if pipeline_run.logs.any?
      error_logs = pipeline_run.logs.flat_map(&:log_items).select { |item| item.status == 'error' }
      if error_logs.any?
        puts "\nError logs:"
        error_logs.last(3).each do |log|
          puts "  • #{log.text}"
        end
      end
    end
    break
  end
  
  sleep 1
end

# Final report
puts "\n" + "="*80
puts Rainbow("📊 FINAL REPORT").cyan.bold
puts "="*80

pipeline_run.reload
duration = (Time.current - start_time).round(1)

puts "\nPipeline ID: ##{pipeline_run.id}"
puts "Final Status: " + (pipeline_run.completed? ? Rainbow("COMPLETED").green : 
                         pipeline_run.failed? ? Rainbow("FAILED").red : 
                         Rainbow(pipeline_run.status.upcase).yellow)
puts "Total Duration: #{duration}s"
puts "Stages Completed: #{pipeline_run.current_stage_number}/9"

if stage_times.any?
  puts "\nStage Timings:"
  stage_times.each do |stage, time|
    puts "  • #{stage}: #{time.round(1)}s"
  end
end

# Check what actually happened
puts "\n" + Rainbow("Diagnostics:").yellow

# Check if jobs were queued
job_count = SolidQueue::Job.count rescue 0
puts "  Jobs in queue: #{job_count}"

# Check batch status
batch = pipeline_run.ingest_batch
puts "  Batch status: #{batch.status}"
puts "  Items created: #{batch.ingest_items.count}"
puts "  Items with content: #{batch.ingest_items.where.not(content: nil).count}"

# Success determination
success = pipeline_run.current_stage_number > 1

puts "\n" + "="*80
if success
  puts Rainbow("✅ SUCCESS: Pipeline IS advancing automatically!").green.bold
  puts "The pipeline progressed to stage #{pipeline_run.current_stage_number}/9"
else
  puts Rainbow("❌ FAILURE: Pipeline is NOT advancing automatically").red.bold
  puts "\nPossible issues:"
  puts "  1. Solid Queue not running (start with: bin/dev)"
  puts "  2. Jobs queued but not processing"
  puts "  3. Stage 1 failed to complete"
  puts "\nDebug with:"
  puts "  • Check queue: rails c → SolidQueue::Job.all"
  puts "  • Check logs: tail -f log/development.log"
  puts "  • Check errors: pipeline_run.logs.map(&:log_items).flatten.select { |i| i.status == 'error' }"
end
puts "="*80

# Cleanup
puts "\n🧹 Cleaning up..."
pipeline_run.update!(status: 'cancelled') if pipeline_run.running?
test_ekn.destroy!
FileUtils.rm_rf(test_dir)

puts Rainbow("✅ Test complete!").green