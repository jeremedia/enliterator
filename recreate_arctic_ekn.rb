#!/usr/bin/env ruby

# Recreate the Arctic Research EKN to match existing Neo4j data
ekn = Ekn.create!(
  name: "Arctic Research Navigator",
  slug: "arctic-research", 
  description: "Arctic geopolitics, strategy, climate research, and resource development analysis across circumpolar nations"
)

puts "✅ Recreated Arctic Research EKN:"
puts "   ID: #{ekn.id}"
puts "   Name: #{ekn.name}"
puts "   Slug: #{ekn.slug}"

# Test connection to Neo4j data
driver = Graph::Connection.instance.driver
session = driver.session(database: "ekn-arctic-research")
result = session.run("MATCH (n) RETURN count(n) as count")
node_count = result.first["count"]

puts "\n📊 Connected to Neo4j data:"
puts "   Database: ekn-arctic-research"
puts "   Total nodes: #{node_count}"

# Verify dashboard will work
stats_service = EknStatsService.new(ekn)
basic_stats = stats_service.basic_stats
puts "\n🎯 Dashboard ready:"
puts "   Entities: #{basic_stats[:total_nodes]}"
puts "   Relationships: #{basic_stats[:total_relationships]}"

session.close