#!/usr/bin/env ruby

puts "\n" + "="*60
puts "STARTING META-ENLITERATOR PIPELINE"
puts "="*60
puts "Timestamp: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}"

# Check for any running pipelines
running = EknPipelineRun.where(status: 'running')
if running.any?
  puts "\n⚠️ WARNING: #{running.count} pipeline(s) already running:"
  running.each { |r| puts "  ##{r.id}: Stage #{r.current_stage} (#{r.stage_duration_minutes} min)" }
  puts "\nContinue anyway? (y/n)"
  response = gets.chomp.downcase
  exit unless response == 'y'
end

# Check Solid Queue status
puts "\nChecking Solid Queue status..."
total_jobs = SolidQueue::Job.count
pending_jobs = SolidQueue::Job.where(finished_at: nil).count
puts "  Total jobs: #{total_jobs}"
puts "  Pending jobs: #{pending_jobs}"

if pending_jobs > 10
  puts "  ⚠️ WARNING: #{pending_jobs} jobs pending. Workers may be stuck."
end

# Check Neo4j connection
puts "\nChecking Neo4j connection..."
begin
  result = Graph::QueryService.new(nil).query("RETURN 1 as test")
  puts "  ✅ Neo4j connected"
rescue => e
  puts "  ❌ Neo4j error: #{e.message}"
  puts "  (This is okay if Neo4j is running - the service may just need a database name)"
end

# Check OpenAI configuration
puts "\nChecking OpenAI configuration..."
[:extraction, :rights_inference, :answer].each do |task|
  model = OpenaiConfig::SettingsManager.model_for(task)
  puts "  #{task}: #{model}"
end

# Start the pipeline
puts "\n" + "-"*60
puts "Starting Meta-Enliterator pipeline..."
puts "-"*60

begin
  pipeline_run = Pipeline::Orchestrator.process_meta_enliterator
  
  puts "\n✅ Pipeline started successfully!"
  puts "  Pipeline ID: ##{pipeline_run.id}"
  puts "  EKN: #{pipeline_run.ekn.name}"
  puts "  Batch: ##{pipeline_run.ingest_batch_id}"
  puts "  Status: #{pipeline_run.status}"
  puts "\nMonitor at: /admin/pipeline_runs/#{pipeline_run.id}"
  
  # Wait a moment and check if job was queued
  sleep 2
  pipeline_run.reload
  
  if pipeline_run.status == 'running'
    puts "\n📊 Initial Status:"
    puts "  Current stage: #{pipeline_run.current_stage}"
    puts "  Stage number: #{pipeline_run.current_stage_number}/9"
    
    # Check if job was actually created
    recent_jobs = SolidQueue::Job.where(created_at: 1.minute.ago..).where(class_name: "Pipeline::IntakeJob")
    if recent_jobs.any?
      puts "  ✅ IntakeJob queued successfully (#{recent_jobs.count} job(s))"
    else
      puts "  ⚠️ WARNING: IntakeJob may not have been queued properly!"
    end
  end
  
rescue => e
  puts "\n❌ Failed to start pipeline: #{e.message}"
  puts e.backtrace.first(5)
  exit 1
end

puts "\n" + "="*60
puts "Pipeline monitoring started. Check admin panel for progress."
puts "="*60