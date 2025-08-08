#!/usr/bin/env ruby

puts "Testing Stage 0 status fix..."
puts "="*60
puts

# Create a minimal test pipeline
ekn = Ekn.find_or_create_by(name: "Stage 0 Test EKN") do |e|
  e.description = "Testing Stage 0 status tracking"
end

batch = ekn.ingest_batches.create!(
  name: "Stage 0 Test Batch - #{Time.current.strftime('%Y%m%d_%H%M')}",
  source_type: "test",
  status: "pending",
  metadata: { test: true }
)

# Create one test item
batch.ingest_items.create!(
  file_path: "/test/file.rb",
  source_hash: SecureRandom.hex,
  media_type: 'code',
  triage_status: 'pending'
)

# Create pipeline
pipeline = EknPipelineRun.create!(
  ekn: ekn,
  ingest_batch: batch,
  status: "initialized"
)

puts "Created pipeline ##{pipeline.id}"
puts "Initial status: #{pipeline.status}"
puts "Current stage: #{pipeline.current_stage} (#{pipeline.current_stage_number})"
puts

puts "Stage statuses before start:"
pipeline.stage_statuses.each do |stage, status|
  puts "  #{stage}: #{status || 'nil'}"
end
puts

# Start the pipeline
puts "Starting pipeline..."
pipeline.start!

puts "\nAfter starting:"
puts "Status: #{pipeline.status}"
puts "Current stage: #{pipeline.current_stage} (#{pipeline.current_stage_number})"
puts

puts "Stage statuses after start:"
pipeline.reload.stage_statuses.each do |stage, status|
  puts "  #{stage}: #{status || 'nil'}"
end

# Check if Stage 0 is marked as completed
if pipeline.stage_statuses['initialized'] == 'completed'
  puts "\n✅ SUCCESS! Stage 0 (initialized/frame) is marked as completed"
else
  puts "\n❌ FAILED! Stage 0 status: #{pipeline.stage_statuses['initialized']}"
end

# Clean up - cancel the pipeline
pipeline.update_column(:status, 'cancelled')
puts "\nTest pipeline cancelled."