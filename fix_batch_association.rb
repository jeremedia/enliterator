#!/usr/bin/env ruby

# Check and fix batch-EKN association
batch = IngestBatch.find(9)
puts "🔍 Batch-EKN Association Check:"
puts "   Batch ID: #{batch.id}"
puts "   Batch Name: #{batch.name}"
puts "   EKN ID: #{batch.ekn_id}"
puts "   EKN Association: #{batch.ekn.present? ? "✅ Present" : "❌ Missing"}"

if batch.ekn.present?
  puts "   EKN Name: #{batch.ekn.name}"
  puts "   EKN Slug: #{batch.ekn.slug}"
  puts "   Neo4j DB Name: #{batch.ekn.neo4j_database_name}"
else
  puts "   ❌ FIXING: Associating batch with Arctic Research EKN"
  ekn = Ekn.find_by(slug: "arctic-research")
  batch.update!(ekn: ekn)
  puts "   ✅ Fixed: Batch now associated with EKN #{ekn.id}"
  puts "   Neo4j DB Name: #{ekn.neo4j_database_name}"
end

puts "\n🚀 Ready to retry graph sync!"