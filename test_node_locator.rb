#!/usr/bin/env ruby

puts "=== Testing NodeLocator ==="

batch = IngestBatch.find(76)
ekn = batch.ekn

locator = Graph::NodeLocator.new(ekn: ekn)

# Test finding different pool types
test_cases = [
  { pool_type: 'Idea', identifier: 'Community Innovation Framework' },
  { pool_type: 'Practical', identifier: 'Continuous improvement.' },
  { pool_type: 'Experience', identifier: 'Represents testimonials, observations, stories and reviews of outcomes.' }
]

puts "\n=== Testing find_node ==="
test_cases.each do |test|
  result = locator.find_node(
    pool_type: test[:pool_type],
    identifier: test[:identifier]
  )
  
  if result
    puts "✅ Found #{test[:pool_type]}: #{locator.canonical_label_for(result[:properties])}"
  else
    puts "❌ Not found: #{test[:pool_type]} - #{test[:identifier]}"
  end
end

# Test verify_nodes_exist
puts "\n=== Testing verify_nodes_exist ==="
source = { pool_type: 'Idea', label: 'Community Innovation Framework' }
target = { pool_type: 'Practical', label: 'Continuous improvement.' }

verification = locator.verify_nodes_exist(source, target)
puts "Source exists: #{verification[:source].present?}"
puts "Target exists: #{verification[:target].present?}"
puts "Both exist: #{verification[:both_exist]}"

# Test identifier properties
puts "\n=== Testing identifier_property_for ==="
['Idea', 'Practical', 'Experience', 'Manifest'].each do |pool|
  prop = locator.identifier_property_for(pool)
  puts "#{pool}: uses '#{prop}' property"
end