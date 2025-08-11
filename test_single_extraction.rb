#!/usr/bin/env ruby

puts "=== DETAILED TEST EXTRACTION - Arctic Research Item 7 ==="

# Get the test item
item = IngestItem.find(7)
batch = item.ingest_batch
ekn = batch.ekn

puts "Target Document:"
puts "  Item ID: #{item.id}"
puts "  Batch: #{batch.name} (ID: #{batch.id})"
puts "  EKN: #{ekn.name}"
puts "  Content Length: #{item.content.length} chars"
puts "  Pool Status: #{item.pool_status}"
puts ""

# Check which model will be selected
model = OpenaiConfig::SettingsManager.model_for(:extraction, content_length: item.content.length)
puts "Selected Model: #{model}"
puts "Reason: Content #{item.content.length} chars #{item.content.length > 400_000 ? '>' : '≤'} 400K threshold"
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
puts ""

# Reset item status  
item.update!(pool_status: 'pending', pool_metadata: nil)
puts "✅ Item #{item.id} ready for fresh extraction"
puts ""

# Now test the enhanced extraction
puts "=== TESTING ENHANCED EXTRACTION ==="

# Test the enhanced extraction tool directly first
puts "Step 1: Testing Enhanced ExtractAndLinkTool directly..."

start_time = Time.current
result = Mcp::EnhancedExtractAndLinkTool.call(
  text: item.content,
  mode: 'extract',
  ekn: ekn
)

duration = Time.current - start_time

puts "Extraction completed in #{duration.round(2)} seconds"
puts ""

if result[:error]
  puts "❌ EXTRACTION FAILED:"
  puts "   Error: #{result[:error]}"
else
  puts "✅ EXTRACTION SUCCEEDED:"
  puts "   Strategy: #{result[:extraction_strategy]}"
  puts "   Total entities: #{result[:summary][:total_extracted]}"
  puts "   Pools found: #{result[:summary][:pools_found]}"
  puts "   Quality score: #{result[:summary][:quality_score]}"
  puts ""
  
  # Show entity breakdown by pool
  entities = result[:entities_extracted] || []
  if entities.any?
    puts "Entity Breakdown by Pool:"
    pool_counts = entities.group_by { |e| e[:pool] }.transform_values(&:count)
    pool_counts.each do |pool, count|
      puts "  #{pool.ljust(12)}: #{count}"
    end
    puts ""
    
    # Show first few entities from each pool
    puts "Sample Entities:"
    pool_counts.keys.first(3).each do |pool|
      pool_entities = entities.select { |e| e[:pool] == pool }.first(2)
      puts "  #{pool}:"
      pool_entities.each do |entity|
        puts "    - #{entity[:name]} (conf: #{entity[:confidence]})"
      end
    end
  end
end

puts ""
puts "=== END DIRECT EXTRACTION TEST ==="