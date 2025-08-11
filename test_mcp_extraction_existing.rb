#!/usr/bin/env ruby
# Test MCP tool extraction with existing conversation

require_relative 'config/environment'

# Use existing conversation 17 that we know exists
conv = Conversation.find(17)
ekn = conv.ekn

puts "Using EKN: #{ekn.name} (#{ekn.slug})"
puts "Conversation ##{conv.id}"

# Ensure MCP is enabled
conv.update_column(:model_config, {
  'use_mcp_tools' => true,
  'model_name' => 'gpt-5',
  'temperature' => 0.7
})

# Add a new test message
msg = conv.messages.create!(
  role: 'user',
  content: 'Search for all Idea nodes in the knowledge graph',
  metadata: { timestamp: Time.current, test: true }
)

puts "Created message ##{msg.id}: #{msg.content}"
puts "\nRunning MCP job with enhanced tool extraction..."

# Run the job
begin
  ChatResponseWithMcpJob.perform_now(conversation_id: conv.id, message_id: msg.id)
rescue => e
  puts "Error during job: #{e.message}"
  puts e.backtrace.first(3)
end

# Check results
assistant_msg = conv.messages.where(role: 'assistant').order(created_at: :desc).first
if assistant_msg
  puts "\n=== RESULTS ==="
  puts "Assistant message ##{assistant_msg.id} created"
  puts "Content preview: #{assistant_msg.content[0..200]}..." if assistant_msg.content
  
  puts "\n=== TOOL EXTRACTION ==="
  puts "Tool calls found: #{assistant_msg.metadata['tool_calls']&.size || 0}"
  puts "MCP events: #{assistant_msg.metadata['mcp_events']&.size || 0}"
  
  if assistant_msg.metadata['tool_calls'].present? && assistant_msg.metadata['tool_calls'].any?
    puts "\n✅ SUCCESS! Tool calls extracted:"
    assistant_msg.metadata['tool_calls'].each_with_index do |tc, i|
      puts "  #{i+1}. #{tc['name']} at #{tc['timestamp']}"
      if tc['arguments']
        puts "     Args: #{tc['arguments'].to_s.truncate(100)}"
      end
    end
  else
    puts "\n❌ NO TOOL CALLS EXTRACTED"
  end
  
  if assistant_msg.metadata['mcp_events'].present?
    puts "\nMCP event types:"
    event_types = assistant_msg.metadata['mcp_events'].map { |e| e['type'] }.tally
    event_types.each do |type, count|
      puts "  - #{type}: #{count}"
    end
    
    # Show tool called events specifically
    tool_events = assistant_msg.metadata['mcp_events'].select { |e| e['type'] == 'tool_called' }
    if tool_events.any?
      puts "\nTool events captured (#{tool_events.size}):"
      tool_events.each do |e|
        puts "  - #{e['name'] || 'unknown'}"
      end
    end
  end
  
  if assistant_msg.metadata['error'].present?
    puts "\n⚠️ Error occurred: #{assistant_msg.metadata['error']}"
  end
else
  puts "No assistant message created!"
end