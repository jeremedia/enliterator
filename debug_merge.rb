#!/usr/bin/env ruby

batch = IngestBatch.find(76)
ekn = batch.ekn

clusterer = Graph::EntityClusterer.new(ekn: ekn, batch: batch)

puts "=== Testing merge_clustering_strategies ==="

# Test the merge directly
all_clusters = clusterer.identify_clusters(strategy: :all)

puts "\nMerged result: #{all_clusters.size} clusters"
by_strategy = all_clusters.group_by { |c| c[:strategy] }
by_strategy.each do |strategy, clusters|
  puts "  #{strategy}: #{clusters.size} clusters"
end

# Now test each strategy individually to compare
puts "\n=== Individual Strategy Results ==="
[:co_occurrence, :structural].each do |strategy|
  begin
    clusters = clusterer.identify_clusters(strategy: strategy)
    puts "#{strategy}: #{clusters.size} clusters"
  rescue => e
    puts "#{strategy}: ERROR - #{e.message}"
  end
end

# Check if lexical is causing the issue
puts "\n=== Testing Lexical (the broken one) ==="
begin
  clusters = clusterer.identify_clusters(strategy: :lexical)
  puts "lexical: #{clusters.size} clusters"
rescue => e
  puts "lexical: ERROR - #{e.message}"
  puts "  This error might be preventing structural from being included!"
end