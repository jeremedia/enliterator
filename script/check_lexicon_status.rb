#!/usr/bin/env ruby

puts '=== CHECKING LEXICON STATUS ==='
batch = IngestBatch.find(30)
items = IngestItem.where(ingest_batch: batch)
puts "Lexicon status breakdown:"
items.group(:lexicon_status).count.each { |status, count| puts "  #{status}: #{count}" }

puts "\n=== CHECKING SAMPLE ITEMS FOR CONTENT ==="
items.limit(5).each do |item|
  puts "Item #{item.id}: lexicon_status=#{item.lexicon_status}, pool_status=#{item.pool_status}, content_length=#{item.content&.length || 'nil'}"
end

# Check if we have extracted items waiting for pool processing
ready_items = items.where(lexicon_status: 'extracted', pool_status: 'pending')
puts "\nItems ready for pool extraction: #{ready_items.count}"

if ready_items.count == 0
  puts "\n⚠️ NO ITEMS READY - Need to run lexicon extraction first"
  
  # Check for completed items we can mark as extracted
  completed_items = items.where(pool_status: 'pending').where.not(content: [nil, ''])
  puts "Items with content but no lexicon status: #{completed_items.count}"
  
  if completed_items.any?
    puts "Marking items as lexicon extracted..."
    completed_items.update_all(lexicon_status: 'extracted')
    puts "Updated #{completed_items.count} items to lexicon_status: 'extracted'"
  end
else
  puts "\n✅ Found #{ready_items.count} items ready for pool extraction"
end