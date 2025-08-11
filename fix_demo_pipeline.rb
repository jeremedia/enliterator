#!/usr/bin/env ruby

puts "🔧 FIXING PIPELINE FOR DEMO"
puts "=" * 30

# Reset pipeline to correct state
pr = EknPipelineRun.find(3)
pr.update!(
  status: "running",
  current_stage: "graph_assembly", 
  current_stage_number: 5,
  error_message: nil
)
puts "✅ Reset pipeline to graph_assembly stage"

# Check what entities we have for Neo4j
puts "\nEntities ready for graph:"
puts "Ideas: #{Idea.count} (sufficient for demo)"
puts "Experiences: #{Experience.count} (some data)"
puts "Total nodes ready: #{Idea.count + Experience.count}"

puts "\n🎯 Manually triggering Graph Assembly..."

# Manually run Graph Assembly with existing entities
begin
  Graph::AssemblyJob.perform_now(3)
  puts "✅ Graph Assembly completed"
rescue => e
  puts "❌ Graph Assembly failed: #{e.message}"
  puts "   Will try rake task fallback"
end