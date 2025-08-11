#!/usr/bin/env ruby

puts "🔧 RETRYING ENTITY PERSISTENCE WITH FIXED SCHEMAS"
puts "=" * 50

# Get our batch  
batch = IngestBatch.find(9)
puts "Batch: #{batch.name}"

# Count current entities
puts "\nCurrent entity counts:"
puts "Ideas: #{Idea.count}"
puts "Manifests: #{Manifest.count}"  
puts "Experiences: #{Experience.count}"
puts "Practicals: #{Practical.count}"
puts "Relationals: #{Relational.count}"

# Re-run pool extraction to capture the failed entities
puts "\n🎯 Re-running Pool Extraction with fixed schemas..."

begin
  # Reset items that had pool extraction completed but entities failed to save
  failed_items = batch.ingest_items.where(pool_status: 'extracted')
  puts "Found #{failed_items.count} items to retry entity persistence"
  
  if failed_items.any?
    # Reset their status so they'll be reprocessed
    failed_items.update_all(pool_status: 'pending')
    puts "✅ Reset #{failed_items.count} items to pending status"
    
    # Re-run pool extraction  
    start_time = Time.current
    Pools::ExtractionJob.perform_now(3)
    duration = (Time.current - start_time).round(2)
    
    puts "✅ Pool extraction retry completed in #{duration} seconds"
  else
    puts "ℹ️  No items need retry"
  end

rescue => e
  puts "❌ Error during retry: #{e.message}"
  puts "   #{e.backtrace.first(3).join("\n   ")}"
end

# Check final counts
puts "\n📊 Final entity counts:"
puts "Ideas: #{Idea.count}"
puts "Manifests: #{Manifest.count}"  
puts "Experiences: #{Experience.count}"
puts "Practicals: #{Practical.count}"
puts "Relationals: #{Relational.count}"
total_entities = Idea.count + Manifest.count + Experience.count + Practical.count + Relational.count
puts "TOTAL: #{total_entities} entities"

puts "\n🎯 Ready for demo!"