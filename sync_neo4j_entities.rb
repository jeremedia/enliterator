#!/usr/bin/env ruby

puts "🔄 RUNNING NEO4J PIPELINE STAGE"
puts "=" * 40

# Check current pipeline state
pr = EknPipelineRun.find(3)
puts "Pipeline Run #3: #{pr.status} - #{pr.current_stage}"

# Reset pipeline to graph_assembly stage if needed
pr.update!(
  status: "running", 
  current_stage: "graph_assembly",
  current_stage_number: 5,
  error_message: nil
)
puts "✅ Reset pipeline to graph_assembly stage"

# Run Graph Assembly Job properly
puts "\n🎯 Executing Graph Assembly Job..."
begin
  Graph::AssemblyJob.perform_now(3)
  puts "✅ Graph Assembly completed!"
  
  # Check results
  ekn = Ekn.find(3)
  stats = EknStatsService.new(ekn)
  basic_stats = stats.basic_stats
  puts "\nFinal Results:"
  puts "  Neo4j nodes: #{basic_stats[:total_nodes]}"
  puts "  Neo4j relationships: #{basic_stats[:total_relationships]}"
  
  pool_dist = stats.pool_distribution
  puts "  Pool distribution:"
  pool_dist.each { |pool| puts "    #{pool[:pool]}: #{pool[:count]}" }
  
rescue => e
  puts "❌ Graph Assembly failed: #{e.message}"
  puts "   #{e.backtrace.first(3).join("\n   ")}"
end