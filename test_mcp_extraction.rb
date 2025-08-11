#!/usr/bin/env ruby
# Test MCP tool extraction

require_relative 'config/environment'

# Create a fresh, properly saved conversation
ekn = Ekn.find_by(slug: 'meta-enliterator') || Ekn.first
unless ekn
  puts "No EKN found!"
  exit 1
end

puts "Using EKN: #{ekn.name} (#{ekn.slug})"

conv = ekn.conversations.create!(
  status: :active,
  last_activity_at: Time.current,
  model_config: {
    'use_mcp_tools' => true,
    'model_name' => 'gpt-5',
    'temperature' => 0.7
  }
)

# Add user message
msg = conv.messages.create!(
  role: 'user',
  content: 'What nodes are available in the knowledge graph?',
  metadata: { timestamp: Time.current }
)

puts "Created conversation ##{conv.id} with message ##{msg.id}"
puts "Running MCP job..."

# Run the job
begin
  ChatResponseWithMcpJob.perform_now(conversation_id: conv.id, message_id: msg.id)
rescue => e
  puts "Error: #{e.message}"
  puts e.backtrace.first(3)
end

# Check results
assistant_msg = conv.messages.where(role: 'assistant').last
if assistant_msg
  puts "\nAssistant message ##{assistant_msg.id} created"
  puts "Content length: #{assistant_msg.content&.length || 0} chars"
  puts "Tool calls found: #{assistant_msg.metadata['tool_calls']&.size || 0}"
  puts "MCP events: #{assistant_msg.metadata['mcp_events']&.size || 0}"
  
  if assistant_msg.metadata['tool_calls'].present?
    puts "\nTool calls:"
    assistant_msg.metadata['tool_calls'].each do |tc|
      puts "  - #{tc['name']} at #{tc['timestamp']}"
      puts "    Args: #{tc['arguments'].to_s.truncate(100)}" if tc['arguments']
    end
  end
  
  if assistant_msg.metadata['mcp_events'].present?
    puts "\nMCP events summary:"
    event_types = assistant_msg.metadata['mcp_events'].map { |e| e['type'] }.tally
    event_types.each do |type, count|
      puts "  - #{type}: #{count}"
    end
  end
  
  if assistant_msg.metadata['error'].present?
    puts "\nError occurred: #{assistant_msg.metadata['error']}"
  end
else
  puts "No assistant message created!"
end