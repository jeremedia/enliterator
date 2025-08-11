#!/usr/bin/env ruby
# Simple test of extraction logic

require_relative 'config/environment'

# Get the last message with MCP events
msg = Message.where(role: 'assistant')
  .where("metadata->>'mcp_events' IS NOT NULL")
  .where("jsonb_array_length(metadata->'mcp_events') > 5")
  .order(created_at: :desc)
  .first

if msg
  puts "Message ##{msg.id} has #{msg.metadata['mcp_events'].size} events"
  puts "Tool calls in metadata: #{msg.metadata['tool_calls']&.size || 0}"
  
  # Simulate the extraction
  tool_calls = []
  events = msg.metadata['mcp_events']
  
  events.each_with_index do |event, idx|
    if event['type'] == 'mcp_call'
      puts "\nFound mcp_call event at index #{idx}:"
      puts "  Keys: #{event.keys.join(', ')}"
      puts "  Name: #{event['name'] || 'nil'}"
      puts "  ID: #{event['id'] || 'nil'}"
      
      if event['name'].present?
        tool_calls << {
          'name' => event['name'],
          'arguments' => event['arguments'],
          'timestamp' => Time.current.strftime("%I:%M:%S %p")
        }
      end
    end
  end
  
  puts "\nWould extract #{tool_calls.size} tool calls"
  tool_calls.each { |tc| puts "  - #{tc['name']}" }
else
  puts "No message found with MCP events"
end