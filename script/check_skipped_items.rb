#!/usr/bin/env ruby

# Script to check why items were skipped during pipeline processing

pipeline_id = ARGV[0]

if pipeline_id.nil?
  puts "Usage: rails runner script/check_skipped_items.rb <pipeline_run_id>"
  exit 1
end

pr = EknPipelineRun.find(pipeline_id)
batch = pr.ingest_batch

puts "="*60
puts "PIPELINE RUN ##{pr.id} - SKIPPED ITEMS REPORT"
puts "="*60
puts

# Check Stage 2: Rights quarantined items
quarantined = batch.ingest_items.where(quarantined: true)
if quarantined.any?
  puts "Stage 2 (Rights) - Quarantined Items: #{quarantined.count}"
  quarantined.each do |item|
    puts "  - #{File.basename(item.file_path)}"
    puts "    Reason: #{item.quarantine_reason}"
  end
  puts
end

# Check Stage 3: Lexicon skipped items
skipped_lexicon = batch.ingest_items.where(pool_status: 'skipped')
if skipped_lexicon.any?
  puts "Stage 3 (Lexicon) - Skipped Items: #{skipped_lexicon.count}"
  puts "(Items whose terms were all duplicates)"
  skipped_lexicon.each do |item|
    puts "  - #{File.basename(item.file_path)}"
    if item.pool_metadata && item.pool_metadata['skip_reason']
      puts "    Reason: #{item.pool_metadata['skip_reason']}"
    end
    if item.lexicon_metadata && item.lexicon_metadata['terms_count']
      puts "    Had #{item.lexicon_metadata['terms_count']} terms extracted (all were duplicates)"
    end
  end
  puts
end

# Summary statistics
puts "="*60
puts "SUMMARY"
puts "="*60
total = batch.ingest_items.count
processed_to_pools = batch.ingest_items.where(pool_status: 'pending').count
extracted_in_pools = batch.ingest_items.where(pool_status: 'extracted').count

puts "Total items: #{total}"
puts "Quarantined (rights issues): #{quarantined.count}"
puts "Skipped (duplicate terms): #{skipped_lexicon.count}"
puts "Sent to pool extraction: #{processed_to_pools}"
puts "Successfully extracted pools: #{extracted_in_pools}"

efficiency = ((processed_to_pools.to_f / total) * 100).round(1)
puts "\nPipeline efficiency: #{efficiency}% of items contributed unique content"