#!/usr/bin/env ruby

# Cancel stuck pipeline and restart with fix applied

puts "=== RESTARTING MICRO PIPELINE ==="
puts "Applying OpenAI response processing fix"
puts

# Cancel the stuck pipeline
old_pr = EknPipelineRun.find(36)
old_pr.update!(status: "cancelled", error_message: "Cancelled to apply fix")
puts "✅ Cancelled pipeline ##{old_pr.id}"

# Cancel any stuck lexicon jobs
stuck_jobs = SolidQueue::ClaimedExecution.joins(:job)
  .where("solid_queue_jobs.class_name LIKE ?", "%Lexicon%")
stuck_jobs.each do |ce|
  ce.destroy
  puts "✅ Cancelled stuck job ##{ce.job_id}"
end

# Use the same EKN and create a new batch
ekn = Ekn.find_by(name: "Micro Test EKN")
puts "\nUsing EKN: #{ekn.name} (ID: #{ekn.id})"

# Select 10 random Ruby files
source_files = Dir.glob("/Volumes/jer4TBv3/enliterator/app/**/*.rb").sample(10)
puts "Selected #{source_files.count} files for new test"

# Create new batch
batch = ekn.ingest_batches.create!(
  name: "Micro Test Batch v2 - #{Time.current.strftime('%Y%m%d_%H%M')}",
  source_type: "codebase",
  status: "pending",
  metadata: {
    test_run: true,
    file_count: source_files.count,
    purpose: "Test GPT-5 with response processing fix"
  }
)

puts "Created batch ##{batch.id}"

# Create IngestItems
source_files.each do |file_path|
  batch.ingest_items.create!(
    file_path: file_path,
    source_hash: Digest::SHA256.hexdigest("#{batch.id}:#{file_path}"),
    media_type: 'code',
    triage_status: 'pending'
  )
end

# Create and start new pipeline run
pipeline_run = EknPipelineRun.create!(
  ekn: ekn,
  ingest_batch: batch,
  status: "initialized"
)

puts "Created pipeline run ##{pipeline_run.id}"

# Start the pipeline
pipeline_run.start!

puts "\n✅ New pipeline started with fix applied!"
puts "\nMonitor with:"
puts "rails runner 'pr = EknPipelineRun.find(#{pipeline_run.id}); puts \"Stage \#{pr.current_stage_number}: \#{pr.current_stage} - \#{pr.status}\"'"