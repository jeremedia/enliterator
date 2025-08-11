#!/usr/bin/env ruby
# Test to understand MCP response structure

require_relative 'config/environment'

# Get the latest assistant message
msg = Message.where(role: 'assistant').order(created_at: :desc).first

if msg
  puts "Message ##{msg.id} created at #{msg.created_at}"
  puts "\nContent (first 200 chars):"
  puts msg.content[0..200] if msg.content
  
  puts "\n=== MCP Events Analysis ==="
  events = msg.metadata['mcp_events'] || []
  
  if events.any?
    puts "Total events: #{events.size}"
    
    # Group by type
    event_types = events.map { |e| e['type'] }.tally
    puts "\nEvent types:"
    event_types.each { |type, count| puts "  #{type}: #{count}" }
    
    # Look at mcp_call events in detail
    mcp_calls = events.select { |e| e['type'] == 'mcp_call' }
    if mcp_calls.any?
      puts "\n=== MCP Call Events (#{mcp_calls.size}) ==="
      mcp_calls.first(3).each_with_index do |event, i|
        puts "\nEvent #{i+1}:"
        event.each do |key, value|
          puts "  #{key}: #{value.inspect}"
        end
      end
    end
  end
  
  puts "\n=== Tool Calls ==="
  tool_calls = msg.metadata['tool_calls'] || []
  puts "Tool calls extracted: #{tool_calls.size}"
  
  if tool_calls.any?
    tool_calls.each_with_index do |tc, i|
      puts "\nTool #{i+1}:"
      tc.each do |key, value|
        puts "  #{key}: #{value.inspect}"
      end
    end
  end
  
  # Check what the actual response object looked like
  puts "\n=== Response Metadata ==="
  puts "Model used: #{msg.metadata['model_used']}"
  puts "Completed at: #{msg.metadata['completed_at']}"
  
  if msg.metadata['usage']
    puts "\nToken usage:"
    msg.metadata['usage'].each do |key, value|
      puts "  #{key}: #{value}"
    end
  end
else
  puts "No assistant messages found"
end