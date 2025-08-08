#!/usr/bin/env ruby
# Script to run a test pipeline with proper EKN association

puts "=== TEST PIPELINE RUN ==="
puts ""

# Find or create a test EKN
ekn = Ekn.find_or_create_by!(name: "Test Navigator") do |e|
  e.description = "Test EKN for pipeline verification"
  e.status = "active"
  e.domain_type = "general"
end

puts "✅ Using EKN ##{ekn.id}: #{ekn.name}"
puts ""

# Create an IngestBatch associated with the EKN
batch = IngestBatch.create!(
  name: "Test Bundle #{Time.current.strftime('%Y%m%d_%H%M%S')}",
  ekn: ekn,
  status: "pending",
  source_path: Rails.root.join("data/test_bundle.zip").to_s
)

puts "✅ Created IngestBatch ##{batch.id}"
puts ""

# Run Stage 1: Intake
puts "🔄 Running Stage 1: Intake..."
begin
  service = Ingest::IntakeService.new(batch)
  result = service.call
  
  if result[:success]
    batch.update!(status: "intake_complete")
    puts "✅ Intake complete: #{result[:message]}"
    puts "   Files discovered: #{result[:file_count]}"
  else
    batch.update!(status: "intake_failed", error_message: result[:error])
    puts "❌ Intake failed: #{result[:error]}"
    exit 1
  end
rescue => e
  puts "❌ Error during intake: #{e.message}"
  puts e.backtrace.first(5).join("\n")
  batch.update!(status: "intake_failed", error_message: e.message)
  exit 1
end

puts ""
puts "=== PIPELINE TEST COMPLETE ==="
puts "Batch ##{batch.id} status: #{batch.reload.status}"
puts "Next step: Run additional stages or check the database"