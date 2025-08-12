#!/usr/bin/env ruby

# Quick test for 15-pool extraction system with small sample

# Use a small, focused sample that should contain multiple entity types
test_content = <<~CONTENT
  Alaska Resource Development - Opportunities to Create Jobs and Strengthen National Security

  FIELD HEARING BEFORE THE COMMITTEE ON ENERGY AND NATURAL RESOURCES
  UNITED STATES SENATE
  ONE HUNDRED FOURTEENTH CONGRESS
  SECOND SESSION
  MARCH 28, 2016

  Senator Murkowski, Chairman of the Committee on Energy and Natural Resources, welcomed 
  participants to Anchorage, Alaska. Dr. Sarah Johnson from the Arctic Research Institute 
  presented findings on climate change impacts in the Beaufort Sea region. 

  The statistical analysis methodology used temperature measurements from weather stations 
  between 2010-2015. Safety protocols required environmental impact assessments before 
  any drilling operations. The Alaska Department of Natural Resources governs all 
  resource extraction activities.
CONTENT

puts "Testing Enhanced Extraction on Congressional Hearing Sample"
puts "Content length: #{test_content.length} characters"
puts "="*60

# Test the updated extraction tool
result = Mcp::EnhancedExtractAndLinkTool.call(
  text: test_content,
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
  
  # Show entities by pool
  by_pool = result[:entities_extracted].group_by { |e| e[:pool] }
  by_pool.each do |pool, entities|
    puts "#{pool.upcase} (#{entities.size}):"
    entities.each do |entity|
      puts "  - #{entity[:name]} (#{entity[:confidence]})"
    end
    puts ""
  end
  
  puts "AVAILABLE POOLS: #{Mcp::EnhancedExtractAndLinkTool::POOLS.join(', ')}"
  puts "MISSING: #{(Mcp::EnhancedExtractAndLinkTool::POOLS - by_pool.keys).join(', ')}"
end