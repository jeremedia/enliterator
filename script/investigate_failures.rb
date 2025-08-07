#!/usr/bin/env ruby

puts '=== INVESTIGATING POOL EXTRACTION FAILURES ==='
batch = IngestBatch.find(30)

# Check failed items
failed_items = batch.ingest_items.where(pool_status: 'failed').limit(5)
puts "Failed items: #{failed_items.count}"

failed_items.each do |item|
  puts "\nItem #{item.id}:"
  puts "  File: #{File.basename(item.file_path)}"
  puts "  Content length: #{item.content&.length || 'nil'}"
  puts "  Pool metadata: #{item.pool_metadata}"
  
  # Check if content exists and is reasonable
  if item.content && item.content.length > 100
    puts "  Content sample: #{item.content[0..100]}..."
  end
end

puts "\n=== CHECKING EXTRACTION SERVICES ==="
# Check if the extraction services exist
begin
  service_class = Pools::EntityExtractionService
  puts "EntityExtractionService found: #{service_class}"
rescue => e
  puts "EntityExtractionService ERROR: #{e.message}"
end

begin
  service_class = Pools::RelationExtractionService  
  puts "RelationExtractionService found: #{service_class}"
rescue => e
  puts "RelationExtractionService ERROR: #{e.message}"
end