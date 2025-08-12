#!/usr/bin/env ruby

# Test script for 15-pool extraction system

item = IngestItem.find(1)
puts "Testing Enhanced Extraction on: #{item.file_path}"
puts "Content length: #{item.content.length} characters"
puts "="*80

# Test the updated extraction tool
result = Mcp::EnhancedExtractAndLinkTool.call(
  text: item.content.first(3000), # Limit to first 3000 chars for test
  mode: "extract"
)

if result[:error]
  puts "ERROR: #{result[:error]}"
else
  puts "EXTRACTION RESULTS:"
  puts "Total entities: #{result[:summary][:total_extracted]}"
  puts "Pools found: #{result[:summary][:pools_found].join(', ')}"
  puts "Quality score: #{result[:summary][:quality_score]}"
  puts ""
  
  # Group by pool type for analysis
  by_pool = result[:entities_extracted].group_by { |e| e[:pool] }
  by_pool.each do |pool, entities|
    puts "#{pool.upcase} (#{entities.size} entities):"
    entities.first(3).each do |entity|
      puts "  - #{entity[:name]} (conf: #{entity[:confidence]})"
    end
    puts "    ... and #{entities.size - 3} more" if entities.size > 3
    puts ""
  end
  
  puts "="*80
  puts "ANALYSIS:"
  puts "- Expected 15 pools available: #{Mcp::EnhancedExtractAndLinkTool::POOLS.size}"
  puts "- Pools found in content: #{by_pool.keys.size}"
  puts "- Missing pools: #{(Mcp::EnhancedExtractAndLinkTool::POOLS - by_pool.keys).join(', ')}"
end