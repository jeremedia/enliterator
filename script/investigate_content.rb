#!/usr/bin/env ruby

puts '=== INVESTIGATING EMPTY CONTENT ==='
batch = IngestBatch.find(30)
items = IngestItem.where(ingest_batch: batch).limit(10)

items.each do |item|
  puts "\nItem #{item.id}:"
  puts "  File path: #{item.file_path}"
  puts "  Source type: #{item.source_type}"
  puts "  Media type: #{item.media_type}"
  puts "  Size bytes: #{item.size_bytes}"
  puts "  Content sample: #{item.content_sample}"
  puts "  Triage status: #{item.triage_status}"
  puts "  Content present: #{!item.content.nil? && !item.content.empty?}"
  
  # Check if file exists
  if item.file_path && File.exist?(item.file_path)
    puts "  File exists: YES"
    puts "  File size: #{File.size(item.file_path)} bytes"
  else
    puts "  File exists: NO"
  end
end

puts "\n=== CHECKING TRIAGE STATUS ==="
puts "Triage status breakdown:"
IngestItem.where(ingest_batch: batch).group(:triage_status).count.each { |status, count| puts "  #{status}: #{count}" }

puts "\n=== CHECKING BATCH METADATA ==="
puts "Batch metadata: #{batch.metadata}"