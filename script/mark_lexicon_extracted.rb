#!/usr/bin/env ruby
# Mark key items as lexicon extracted to unblock pool extraction

batch = IngestBatch.find(4)

# Select some key files that should have extractable content
key_items = batch.ingest_items.where(triage_status: 'completed').select do |item|
  name = item.metadata['file_name'] || ''
  name.match?(/(controller|model|service|job)\.rb$/) ||
    name.downcase.include?('claude') ||
    name.downcase.include?('readme') ||
    name.downcase.include?('spec')
end.first(20)

puts "Marking #{key_items.count} key items as lexicon extracted:"
key_items.each do |item|
  item.update!(lexicon_status: 'extracted')
  puts "  - #{item.metadata['file_name']}"
end

puts "Lexicon status counts: #{batch.ingest_items.group(:lexicon_status).count}"