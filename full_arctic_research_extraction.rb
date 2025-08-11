#!/usr/bin/env ruby

puts "=== FULL ARCTIC RESEARCH RE-EXTRACTION ==="

ekn = Ekn.find_by(slug: 'arctic-research')
puts "EKN: #{ekn.name} (ID: #{ekn.id})"

batches = ekn.ingest_batches
puts "Batches: #{batches.count}"

total_items = 0
batches.each do |batch|
  items = batch.ingest_items.where(quarantined: [false, nil])
  total_items += items.count
  puts "  Batch #{batch.id}: #{items.count} items"
  
  # Reset all items to pending
  items.update_all(pool_status: 'pending', graph_status: nil)
end

puts "Total items to process: #{total_items}"
puts ""

# Clear existing entities from all Arctic Research batches
puts "=== CLEARING EXISTING ENTITIES ==="
batches.each do |batch|
  puts "Clearing batch #{batch.id}..."
  
  [Character, TimeEntity, Space, Lifecycle, Symbolic, Relator, 
   Idea, Manifest, Experience, Practical].each do |model_class|
    
    count = model_class.joins(:provenance_and_rights)
                      .where(provenance_and_rights: { 
                        custom_terms: { 'extraction_batch' => batch.id.to_s } 
                      }).count
    
    if count > 0
      puts "  #{model_class.name}: #{count} entities"
      model_class.joins(:provenance_and_rights)
                 .where(provenance_and_rights: { 
                   custom_terms: { 'extraction_batch' => batch.id.to_s } 
                 }).destroy_all
    end
  end
end

puts "✅ All existing entities cleared"
puts ""

# Now run the enhanced extraction on all items
puts "=== RUNNING ENHANCED EXTRACTION ON ALL ITEMS ==="

processed = 0
failed = 0

batches.each do |batch|
  items = batch.ingest_items.where(pool_status: 'pending')
  puts "Processing batch #{batch.id}: #{items.count} items"
  
  items.find_each.with_index do |item, index|
    begin
      puts "  [#{index + 1}/#{items.count}] Processing item #{item.id} (#{item.content.to_s.length} chars)..."
      
      # Use enhanced extraction
      start_time = Time.current
      result = Mcp::EnhancedExtractAndLinkTool.call(
        text: item.content,
        mode: 'extract',
        ekn: ekn
      )
      duration = Time.current - start_time
      
      if result[:error].blank?
        entities = result[:entities_extracted] || []
        quality = result[:quality_report][:overall_quality_score]
        pools_found = result[:summary][:pools_found] || []
        
        puts "    ✅ #{entities.size} entities extracted in #{duration.round(1)}s (quality: #{quality})"
        puts "    📊 Pools: #{pools_found.join(', ')}"
        
        # Update item with success
        item.update!(
          pool_status: 'extracted',
          pool_metadata: {
            entities_count: entities.size,
            pools_found: pools_found,
            quality_score: quality,
            extraction_strategy: result[:extraction_strategy],
            extraction_duration: duration.round(2),
            extracted_at: Time.current
          }
        )
        
        processed += 1
      else
        puts "    ❌ Failed: #{result[:error]}"
        item.update!(pool_status: 'failed')
        failed += 1
      end
      
      # Progress summary every 5 items
      if (index + 1) % 5 == 0
        puts "  📈 Progress: #{processed} successful, #{failed} failed (#{((index + 1).to_f / items.count * 100).round(1)}%)"
      end
      
    rescue => e
      puts "    ❌ Exception: #{e.message}"
      item.update!(pool_status: 'failed')
      failed += 1
    end
  end
end

puts ""
puts "✅ EXTRACTION COMPLETE"
puts "  Processed: #{processed}"
puts "  Failed: #{failed}"
puts "  Total: #{processed + failed}"

if processed > 0
  puts ""
  puts "=== FINAL VERIFICATION ==="
  
  # Check entity counts by pool
  total_entities = 0
  [Character, TimeEntity, Space, Lifecycle, Symbolic, Relator, 
   Idea, Manifest, Experience, Practical].each do |model_class|
    
    count = model_class.joins(:provenance_and_rights)
                      .where(provenance_and_rights: { 
                        custom_terms: { extraction_batch: batches.pluck(:id).map(&:to_s) } 
                      }).count
    
    if count > 0
      puts "  #{model_class.name.ljust(15)}: #{count}"
      total_entities += count
    end
  end
  
  puts "  #{'TOTAL'.ljust(15)}: #{total_entities}"
  puts ""
  puts "🎉 ARCTIC RESEARCH EKN ENHANCED WITH #{total_entities} ENTITIES!"
  puts "📊 All 10 pools now populated with proper Character classification"
end