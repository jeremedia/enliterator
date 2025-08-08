#!/usr/bin/env ruby

# Micro pipeline test with just 10 files to save credits

puts "=== MICRO PIPELINE TEST ==="
puts "Testing with just 10 files to validate GPT-5 configuration"
puts

# Get or create a test EKN
ekn = Ekn.find_or_create_by(name: "Micro Test EKN") do |e|
  e.description = "Small test EKN for pipeline validation"
end

puts "Using EKN: #{ekn.name} (ID: #{ekn.id})"

# Select 10 random Ruby files from the codebase
source_files = Dir.glob("/Volumes/jer4TBv3/enliterator/app/**/*.rb").sample(10)

puts "Selected #{source_files.count} files:"
source_files.each do |f|
  puts "  - #{File.basename(f)}"
end
puts

# Create a new batch with just these files
batch = ekn.ingest_batches.create!(
  name: "Micro Test Batch - #{Time.current.strftime('%Y%m%d_%H%M')}",
  source_type: "codebase",
  status: "pending",
  metadata: {
    test_run: true,
    file_count: source_files.count,
    purpose: "Validate GPT-5 configuration and temperature fix"
  }
)

puts "Created batch ##{batch.id}"

# Create IngestItems for each file
source_files.each do |file_path|
  batch.ingest_items.create!(
    file_path: file_path,
    source_hash: Digest::SHA256.hexdigest("#{batch.id}:#{file_path}"),
    media_type: 'code',
    triage_status: 'pending'
  )
end

puts "Created #{batch.ingest_items.count} ingest items"
puts

# Create and start pipeline run
pipeline_run = EknPipelineRun.create!(
  ekn: ekn,
  ingest_batch: batch,
  status: "initialized"
)

puts "Created pipeline run ##{pipeline_run.id}"
puts

# Start the pipeline
pipeline_run.start!

puts "✅ Pipeline started!"
puts
puts "This micro test will:"
puts "1. Process 10 files through all 9 stages"
puts "2. Use GPT-5 models (no temperature parameter)"
puts "3. Complete much faster than full 266-file batch"
puts "4. Validate the entire pipeline flow"
puts
puts "Monitor with: rails runner 'pr = EknPipelineRun.find(#{pipeline_run.id}); puts \"Stage: \#{pr.current_stage} (\#{pr.current_stage_number})\"; puts \"Status: \#{pr.status}\"'"