#!/usr/bin/env ruby

puts "=== TESTING REAL PIPELINE ON SINGLE ITEM - Arctic Research Item 7 ==="

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

# Set all other items in the batch to 'skipped' so only our test item gets processed
batch.ingest_items.where.not(id: item.id).update_all(pool_status: 'skipped')

puts "✅ Item #{item.id} ready, other items skipped"
puts ""

# Create a real pipeline run for pool filling stage
puts "=== CREATING REAL PIPELINE RUN ==="

pipeline_run = EknPipelineRun.create!(
  ekn: ekn,
  stage: 'pool_filling',
  status: 'running',
  started_at: Time.current,
  batch_id: batch.id
)

puts "Created pipeline run #{pipeline_run.id} for stage: pool_filling"
puts ""

# Run the actual pool filling job
puts "=== RUNNING POOLS::EXTRACTION JOB ==="

start_time = Time.current

begin
  # Execute the job with the real pipeline run
  Pools::ExtractionJob.perform_now(pipeline_run.id)
  
  duration = Time.current - start_time
  puts "✅ Pipeline job completed in #{duration.round(2)} seconds"
  
rescue => e
  puts "❌ Pipeline job error: #{e.message}"
  puts "   Backtrace: #{e.backtrace.first(5).join("\n   ")}"
end

# Check pipeline run status
pipeline_run.reload
puts ""
puts "Pipeline Run Status:"
puts "  Status: #{pipeline_run.status}"
puts "  Stage: #{pipeline_run.stage}"
puts "  Logs: #{pipeline_run.log_entries.count} entries"

puts ""
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
      label = entity.label rescue (entity.goal rescue 'N/A')
      puts "    - #{label}"
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
puts "  pool_metadata keys: #{item.pool_metadata&.keys}"

puts ""
puts "=== END REAL PIPELINE TEST ==="