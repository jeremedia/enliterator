#!/usr/bin/env ruby

puts "Creating new pipeline with real source files..."
ekn = Ekn.find(36)
batch = IngestBatch.create!(
  ekn: ekn, 
  name: "Real Files Test - #{Time.now.strftime('%Y%m%d_%H%M')}", 
  status: "pending",
  source_type: "file_system"
)

# Get 10 real Ruby files from the app directory
files = Dir["/Volumes/jer4TBv3/enliterator/app/**/*.rb"].first(10)
puts "Found #{files.size} files to process"

files.each do |f|
  content = File.read(f)
  batch.ingest_items.create!(
    file_path: f, 
    content: content, 
    triage_status: "pending",
    lexicon_status: "pending"
  )
  puts "  Added: #{f}"
end

pr = EknPipelineRun.create!(
  ekn: ekn, 
  ingest_batch: batch, 
  status: "initialized"
)

pr.start!
puts "\nStarted pipeline ##{pr.id} with #{batch.ingest_items.count} real files"
puts "Status: #{pr.status}"
puts "Current stage: #{pr.current_stage}"