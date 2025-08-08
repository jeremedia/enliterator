# Script to create and start a new pipeline run
ekn = Ekn.last
batch = ekn.ingest_batches.last

puts "Using EKN: #{ekn.name} (ID: #{ekn.id})"
puts "Using Batch: #{batch.name} (ID: #{batch.id})"

pr = EknPipelineRun.create!(
  ekn: ekn,
  ingest_batch: batch,
  status: "initialized"
)

puts "Created Pipeline Run ##{pr.id}"
pr.start!
puts "Pipeline started!"
puts "Status: #{pr.status}"
puts "Current stage: #{pr.current_stage}"