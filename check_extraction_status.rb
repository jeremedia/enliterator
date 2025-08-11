#!/usr/bin/env ruby

# Check entity extraction status for our batch
batch = IngestBatch.find(9)
puts "🔍 ENTITY EXTRACTION STATUS CHECK"
puts "="*50

puts "📊 Batch Overview:"
puts "   Batch: #{batch.name}"
puts "   Items: #{batch.ingest_items.count}"
puts "   Content chars: #{batch.ingest_items.sum(:content_length_chars)}"

puts "\n📈 Processing Status:"
items = batch.ingest_items
puts "   Triage completed: #{items.where(triage_status: 'completed').count}/#{items.count}"
puts "   Lexicon completed: #{items.where(lexicon_status: 'completed').count}/#{items.count}"
puts "   Pool extraction completed: #{items.where(pool_status: 'completed').count}/#{items.count}"

puts "\n🔍 Sample Item Analysis:"
sample_item = items.where('content_length_chars > 50000').first
if sample_item
  puts "   Sample: #{File.basename(sample_item.file_path)}"
  puts "   Content: #{sample_item.content_length_chars} chars"
  puts "   Triage: #{sample_item.triage_status}"
  puts "   Lexicon: #{sample_item.lexicon_status}"
  puts "   Pool: #{sample_item.pool_status}"
else
  puts "   No large items found"
end

puts "\n🎯 Next Steps:"
if items.where(lexicon_status: 'completed').count == 0
  puts "   ➡️ Need to run lexicon extraction first"
elsif items.where(pool_status: 'completed').count == 0
  puts "   ➡️ Need to run pool extraction first" 
else
  puts "   ➡️ Ready for graph sync"
end