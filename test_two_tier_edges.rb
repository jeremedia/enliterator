#!/usr/bin/env ruby

puts "=== Testing Two-Tier Edge Model ==="

batch = IngestBatch.find(76)
ekn = batch.ekn
manager = Graph::RelationshipManager.new(ekn: ekn)

# First, check current edge metrics
puts "\n=== Current Edge Metrics ==="
metrics = manager.edge_metrics
puts "Total relationships: #{metrics[:total]}"
puts "By status:"
metrics[:by_status].each do |status, count|
  puts "  #{status}: #{count}"
end
puts "Verification rate: #{metrics[:verification_rate]}%"

# List some candidate relationships
puts "\n=== Sample Candidate Relationships ==="
candidates = manager.list_candidates(limit: 5)
if candidates.empty?
  puts "No candidate relationships found"
else
  candidates.each_with_index do |rel, i|
    puts "#{i+1}. #{rel[:source][:label]} -[#{rel[:verb]}]-> #{rel[:target][:label]}"
    puts "   Confidence: #{rel[:confidence]}, Strategy: #{rel[:strategy]}"
  end
  
  # Promote the first candidate to verified
  if candidates.any?
    first_candidate = candidates.first
    puts "\n=== Promoting First Candidate to Verified ==="
    success = manager.promote_to_verified(
      first_candidate[:id],
      promoted_by: 'test_script',
      reason: 'Testing two-tier model'
    )
    
    if success
      puts "✅ Successfully promoted relationship ##{first_candidate[:id]} to verified"
    else
      puts "❌ Failed to promote relationship"
    end
  end
end

# List verified relationships
puts "\n=== Sample Verified Relationships ==="
verified = manager.list_verified(limit: 5)
if verified.empty?
  puts "No verified relationships found"
else
  verified.each_with_index do |rel, i|
    puts "#{i+1}. #{rel[:source][:label]} -[#{rel[:verb]}]-> #{rel[:target][:label]}"
    puts "   Path: #{rel[:path_sentence]}"
    puts "   Verified by: #{rel[:verified_by]} at #{rel[:verified_at]}"
  end
end

# Check updated metrics
puts "\n=== Updated Edge Metrics ==="
updated_metrics = manager.edge_metrics
puts "Total relationships: #{updated_metrics[:total]}"
puts "By status:"
updated_metrics[:by_status].each do |status, count|
  puts "  #{status}: #{count}"
end
puts "Verification rate: #{updated_metrics[:verification_rate]}%"

if updated_metrics[:verified_verbs].any?
  puts "Verified verbs:"
  updated_metrics[:verified_verbs].each do |verb, count|
    puts "  #{verb}: #{count}"
  end
end