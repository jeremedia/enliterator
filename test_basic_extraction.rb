#!/usr/bin/env ruby

# Test the basic entity extraction service

test_content = <<~CONTENT
  Senator Murkowski, Chairman of the Committee on Energy and Natural Resources, welcomed 
  participants to Anchorage, Alaska. Dr. Sarah Johnson from the Arctic Research Institute 
  presented findings on climate change impacts in the Beaufort Sea region. 

  The statistical analysis methodology used temperature measurements from weather stations 
  between 2010-2015. Safety protocols required environmental impact assessments before 
  any drilling operations.
CONTENT

puts "Testing Basic Entity Extraction Service"
puts "Content: #{test_content.length} chars"
puts "Available pools: #{Pools::EntityExtractionService::POOL_DESCRIPTIONS.keys.size}"
puts "="*50

begin
  service = Pools::EntityExtractionService.new(
    content: test_content,
    lexicon_context: [],
    source_metadata: { test: true }
  )
  
  result = service.call
  
  if result[:success]
    puts "SUCCESS!"
    puts "Entities extracted: #{result[:entities].size}"
    
    by_pool = result[:entities].group_by { |e| e[:pool_type] }
    by_pool.each do |pool, entities|
      puts "#{pool.upcase}: #{entities.size} entities"
      entities.each do |entity|
        puts "  - #{entity[:attributes][:label]} (#{entity[:confidence]})"
      end
    end
    
    puts ""
    puts "All available pools: #{Pools::EntityExtractionService::POOL_DESCRIPTIONS.keys.join(', ')}"
    puts "Found pools: #{by_pool.keys.join(', ')}"
  else
    puts "FAILED: #{result}"
  end
rescue => e
  puts "ERROR: #{e.message}"
  puts e.backtrace.first(5)
end