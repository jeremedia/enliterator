#!/usr/bin/env ruby

puts "🔍 INVESTIGATING POOL/BRIDGE DISCREPANCY"
puts "=" * 50

# Check actual dashboard stats
ekn = Ekn.find(3)
stats = EknStatsService.new(ekn)
basic_stats = stats.basic_stats

puts "EknStatsService Reports:"
puts "  Total nodes: #{basic_stats[:total_nodes]}"
puts "  Total relationships: #{basic_stats[:total_relationships]}"

# Check what the actual pool distribution shows
pool_dist = stats.pool_distribution
puts "\nPool Distribution:"
pool_dist.each { |pool| puts "  #{pool[:pool]}: #{pool[:count]} (#{pool[:percentage]}%)" }

# Check Neo4j directly  
puts "\nDirect Neo4j Query:"
begin
  conn = Graph::Connection.instance
  result = conn.query("
    MATCH (n) 
    RETURN labels(n)[0] as label, count(n) as count 
    ORDER BY count DESC
  ")
  puts "Node counts by label:"
  result.each { |row| puts "    #{row['label']}: #{row['count']}" }
rescue => e
  puts "  Neo4j error: #{e.message}"
end

# Check relationships
puts "\nRelationship Query:"
begin
  rel_result = conn.query("
    MATCH ()-[r]->() 
    RETURN type(r) as rel_type, count(r) as count 
    ORDER BY count DESC LIMIT 10
  ")
  puts "Top relationships:"
  rel_result.each { |row| puts "    #{row['rel_type']}: #{row['count']}" }
rescue => e
  puts "  Neo4j relationship error: #{e.message}"
end

puts "\nPostgreSQL Entity Counts:"
puts "  Ideas: #{Idea.count}"
puts "  Manifests: #{Manifest.count}" 
puts "  Experiences: #{Experience.count}"
puts "  Practicals: #{Practical.count}"
puts "  Total: #{Idea.count + Manifest.count + Experience.count + Practical.count}"