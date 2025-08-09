#!/usr/bin/env ruby

batch = IngestBatch.find(76)
ekn = batch.ekn

puts "=== Debugging Clustering Strategies ==="
puts "Batch: #{batch.name} (ID: #{batch.id})"
puts "EKN: #{ekn.name}"

# Check ingest items
puts "\n=== Ingest Items ==="
puts "Total items: #{batch.ingest_items.count}"
puts "Items with file_path: #{batch.ingest_items.where.not(file_path: nil).count}"
puts "Items with content: #{batch.ingest_items.where.not(content: nil).count}"

# Check sample items
puts "\nSample items:"
batch.ingest_items.limit(3).each do |item|
  puts "  Item ##{item.id}: file_path=#{item.file_path.present? ? 'YES' : 'NO'}, size=#{item.content&.size || 0}"
end

# Test each clustering strategy manually
clusterer = Graph::EntityClusterer.new(ekn: ekn, batch: batch)

puts "\n=== Testing Each Strategy ==="

[:co_occurrence, :proximity, :lexical, :structural].each do |strategy|
  begin
    clusters = clusterer.identify_clusters(strategy: strategy)
    puts "#{strategy}: Found #{clusters.size} clusters"
    if clusters.any?
      puts "  Sample cluster: #{clusters.first[:entities].size} entities, confidence: #{clusters.first[:confidence]}"
    end
  rescue => e
    puts "#{strategy}: ERROR - #{e.message}"
  end
end

# Check ProvenanceAndRights for extraction data
puts "\n=== ProvenanceAndRights Check ==="
pr_with_extraction = ProvenanceAndRights.where("custom_terms ? 'extraction_batch'")
                                        .where("custom_terms ->> 'extraction_batch' = ?", batch.id.to_s)
puts "P&R records with extraction_batch=#{batch.id}: #{pr_with_extraction.count}"

pr_with_item = pr_with_extraction.where("custom_terms ? 'extraction_item'")
puts "P&R records with extraction_item: #{pr_with_item.count}"

# Sample extraction items
puts "\nSample extraction_item values:"
pr_with_item.limit(5).each do |pr|
  puts "  Item: #{pr.custom_terms['extraction_item']}"
end