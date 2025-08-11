#!/usr/bin/env ruby

puts "=== TESTING FULL EXTRACTION PIPELINE - Arctic Research Item 7 ==="

# Get the test item
item = IngestItem.find(7)
batch = item.ingest_batch
ekn = batch.ekn

puts "Target Document:"
puts "  Item ID: #{item.id}"
puts "  Batch: #{batch.name} (ID: #{batch.id})"
puts "  EKN: #{ekn.name}"
puts "  Content Length: #{item.content.length} chars"
puts ""

# Clear any existing entities for this item first
puts "=== Clearing existing entities for Item #{item.id} ==="

existing_count = 0
[Character, TimeEntity, Space, Lifecycle, Symbolic, Relator, 
 Idea, Manifest, Experience, Practical].each do |model_class|
  
  count = model_class.joins(:provenance_and_rights)
                    .where(provenance_and_rights: { 
                      custom_terms: { "extraction_item" => item.id.to_s } 
                    }).count
  
  if count > 0
    puts "  #{model_class.name}: #{count} existing"
    existing_count += count
    
    # Delete them
    model_class.joins(:provenance_and_rights)
               .where(provenance_and_rights: { 
                 custom_terms: { "extraction_item" => item.id.to_s } 
               }).destroy_all
  end
end

puts "  Cleared #{existing_count} existing entities"

# Reset item status  
item.update!(pool_status: 'pending', pool_metadata: nil)
puts "✅ Item #{item.id} ready for full pipeline test"
puts ""

# Test the full extraction job
puts "=== TESTING FULL EXTRACTION JOB ==="

puts "Step 1: Running Pools::ExtractionJob directly on single item..."

start_time = Time.current

# Create a mock pipeline run for the job
require 'ostruct'
pipeline_run = OpenStruct.new(
  id: 999,
  batch: batch,
  ekn: ekn,
  stage: 'pool_filling',
  run_log: []
)

begin
  # Create the job instance and run it
  job = Pools::ExtractionJob.new
  
  # Manually set up the instance variables that would normally be set by BaseJob
  job.instance_variable_set(:@pipeline_run, pipeline_run)
  job.instance_variable_set(:@batch, batch)
  job.instance_variable_set(:@ekn, ekn)
  job.instance_variable_set(:@extracted_entities, [])  # Initialize empty array
  
  # Call the extraction method directly on our test item
  job.send(:extract_entities_from_item, item)
  
  # Now save entities to database (ExtractionJob should have populated @extracted_entities)
  job.send(:save_entities_to_database)
  
  puts "✅ ExtractionJob completed successfully"
  
rescue => e
  puts "❌ ExtractionJob error: #{e.message}"
  puts "   Backtrace: #{e.backtrace.first(3).join("\n   ")}"
end

duration = Time.current - start_time
puts "Pipeline test completed in #{duration.round(2)} seconds"
puts ""

# Verify entities were saved to database
puts "=== VERIFYING ENTITIES SAVED TO DATABASE ==="

total_saved = 0
[Character, TimeEntity, Space, Lifecycle, Symbolic, Relator, 
 Idea, Manifest, Experience, Practical].each do |model_class|
  
  count = model_class.joins(:provenance_and_rights)
                    .where(provenance_and_rights: { 
                      custom_terms: { "extraction_item" => item.id.to_s } 
                    }).count
  
  if count > 0
    puts "✅ #{model_class.name.ljust(15)}: #{count} saved"
    total_saved += count
    
    # Show sample entities
    samples = model_class.joins(:provenance_and_rights)
                        .where(provenance_and_rights: { 
                          custom_terms: { "extraction_item" => item.id.to_s } 
                        }).limit(2)
    
    samples.each do |entity|
      puts "    - #{entity.label || entity.respond_to?(:goal) ? entity.goal : 'N/A'}"
    end
  else
    puts "⚠️  #{model_class.name.ljust(15)}: 0 saved"
  end
end

puts ""
puts "#{total_saved > 0 ? '✅' : '❌'} TOTAL ENTITIES SAVED: #{total_saved}"

# Check item status
item.reload
puts ""
puts "Item Status After Pipeline:"
puts "  pool_status: #{item.pool_status}"
puts "  graph_status: #{item.graph_status}"
puts "  pool_metadata: #{item.pool_metadata}"

puts ""
puts "=== END FULL PIPELINE TEST ==="