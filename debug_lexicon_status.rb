#!/usr/bin/env ruby

batch = IngestBatch.find(9)
puts "🔍 LEXICON STATUS ANALYSIS"
puts "=" * 40

items = batch.ingest_items
puts "Total items: #{items.count}"
puts "Lexicon status breakdown:"
puts "  extracted: #{items.where(lexicon_status: "extracted").count}"
puts "  pending: #{items.where(lexicon_status: [nil, "pending"]).count}"
puts "  completed: #{items.where(lexicon_status: "completed").count}"

puts "\nTriage status:"
puts "  completed: #{items.where(triage_status: "completed").count}"

puts "\nSample item details:"
item = items.first
puts "  Item #{item.id}:"
puts "    Triage: #{item.triage_status}"
puts "    Lexicon: #{item.lexicon_status || "nil"}"
puts "    Rights ID: #{item.provenance_and_rights_id}"
puts "    Content size: #{item.content&.length || 0} chars"
puts "    Has content?: #{!item.content.blank?}"

puts "\nLexicon job query logic check:"
ready_items = batch.ingest_items
  .where(triage_status: 'completed')
  .where(lexicon_status: ['pending', nil])  
  .where(quarantined: [false, nil])
puts "Items matching job criteria: #{ready_items.count}"

if ready_items.count > 0
  puts "Sample ready item:"
  puts "  ID: #{ready_items.first.id}"
  puts "  Triage: #{ready_items.first.triage_status}"
  puts "  Lexicon: #{ready_items.first.lexicon_status || "nil"}"
  puts "  Quarantined: #{ready_items.first.quarantined || false}"
end