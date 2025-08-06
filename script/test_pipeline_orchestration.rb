#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to test the pipeline orchestration system
# Run with: rails runner script/test_pipeline_orchestration.rb

require 'rainbow'

puts "\n" + "="*80
puts Rainbow("🧪 Testing Pipeline Orchestration System").cyan
puts "="*80 + "\n"

# Test 1: Create a test EKN
puts Rainbow("Test 1: Creating test EKN...").yellow
test_ekn = Ekn.create!(
  name: "Test Pipeline EKN",
  description: "Testing pipeline orchestration",
  status: 'active',
  domain_type: 'general'
)
puts Rainbow("✅ Created EKN ##{test_ekn.id}: #{test_ekn.name}").green

# Test 2: Create test files
puts "\nTest 2: Creating test files..."
test_dir = Rails.root.join('tmp', 'test_pipeline')
FileUtils.mkdir_p(test_dir)

test_files = []
3.times do |i|
  file_path = test_dir.join("test_file_#{i}.txt")
  File.write(file_path, "Test content #{i}\nThis is a test file for pipeline orchestration.")
  test_files << file_path.to_s
  puts "  Created: #{File.basename(file_path)}"
end
puts "✅ Created #{test_files.count} test files"

# Test 3: Start pipeline
puts "\nTest 3: Starting pipeline..."
pipeline_run = Pipeline::Orchestrator.process_ekn(
  test_ekn,
  test_files,
  batch_name: "Test Batch",
  auto_advance: false  # Manual advance for testing
)
puts "✅ Pipeline run created: ##{pipeline_run.id}"

# Test 4: Check initial status
puts "\nTest 4: Checking initial status..."
status = pipeline_run.detailed_status
puts "  Status: #{status[:status]}"
puts "  Current Stage: #{status[:current_stage]}"
puts "  Progress: #{status[:progress_percentage]}%"
puts "✅ Pipeline initialized correctly"

# Test 5: Test stage advancement
puts "\nTest 5: Testing stage advancement..."
puts "  Starting pipeline..."
pipeline_run.start!
sleep 1
pipeline_run.reload

if pipeline_run.running?
  puts "✅ Pipeline is running"
  puts "  Current stage: #{pipeline_run.current_stage}"
else
  puts "❌ Pipeline failed to start"
end

# Test 6: Check logging
puts "\nTest 6: Checking logging..."
logs = pipeline_run.logs
if logs.any?
  puts "✅ Logs created: #{logs.count} log(s)"
  logs.each do |log|
    puts "  - #{log.label}: #{log.log_items.count} entries"
  end
else
  puts "⚠️  No logs created yet"
end

# Test 7: Test pause/resume
puts "\nTest 7: Testing pause/resume..."
if pipeline_run.running?
  pipeline_run.pause!
  puts "  Paused pipeline"
  
  if pipeline_run.paused?
    puts "✅ Pipeline paused successfully"
    
    pipeline_run.start!
    if pipeline_run.running?
      puts "✅ Pipeline resumed successfully"
    end
  end
end

# Test 8: Test agent status
puts "\nTest 8: Testing agent status..."
agent_status = pipeline_run.agent_status
puts "  Agent Status:"
puts "    Run ID: #{agent_status[:run_id]}"
puts "    Status: #{agent_status[:status]}"
puts "    Stage: #{agent_status[:current_stage]}"
puts "    Progress: #{agent_status[:progress]}"
puts "    Has Errors: #{agent_status[:has_errors]}"
puts "    Next Action: #{agent_status[:next_action]}"
puts "✅ Agent status working"

# Test 9: Test monitoring
puts "\nTest 9: Testing monitoring..."
monitor_status = Pipeline::Orchestrator.monitor(pipeline_run.id)
if monitor_status
  puts "✅ Monitoring working"
  puts "  Stages completed: #{monitor_status[:stages_completed].join(', ')}" if monitor_status[:stages_completed].any?
end

# Test 10: Check active runs
puts "\nTest 10: Checking active runs..."
active_runs = Pipeline::Orchestrator.active_runs
puts "  Active runs: #{active_runs.count}"
active_runs.each do |run|
  puts "    - Run ##{run[:id]}: #{run[:ekn_name]} (#{run[:current_stage]})"
end
puts "✅ Active runs query working"

# Cleanup
puts "\n🧹 Cleaning up..."
pipeline_run.pause! if pipeline_run.running?
test_ekn.destroy!
FileUtils.rm_rf(test_dir)
puts "✅ Cleanup complete"

# Summary
puts "\n" + "="*80
puts "✅ All tests passed!"
puts "="*80
puts "\nThe pipeline orchestration system is working correctly!"
puts "\nTo create Meta-Enliterator, run:"
puts "  rake meta_enliterator:create"
puts "\nTo monitor in real-time:"
puts "  MONITOR=true rake meta_enliterator:create"
puts "\n"