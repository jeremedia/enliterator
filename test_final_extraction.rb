#!/usr/bin/env ruby
# Final test of tool extraction

require_relative 'config/environment'

conv = Conversation.find(17)
msg = conv.messages.create!(
  role: 'user',
  content: 'Search for Idea nodes',
  metadata: { timestamp: Time.current, test: true }
)

puts "Running MCP job for message ##{msg.id}..."
ChatResponseWithMcpJob.perform_now(conversation_id: conv.id, message_id: msg.id)

# Check the result
assistant_msg = conv.messages.where(role: 'assistant').order(created_at: :desc).first
if assistant_msg
  tool_calls = assistant_msg.metadata['tool_calls'] || []
  mcp_events = assistant_msg.metadata['mcp_events'] || []
  
  puts "\n=== RESULTS ==="
  puts "✅ Tool calls extracted: #{tool_calls.size}"
  puts "MCP events: #{mcp_events.size}"
  
  # Show MCP call events
  mcp_call_events = mcp_events.select { |e| e['type'] == 'mcp_call' }
  puts "MCP call events: #{mcp_call_events.size}"
  
  if tool_calls.any?
    puts "\n🎉 TOOL CALLS SUCCESSFULLY DISPLAYED:"
    tool_calls.each_with_index do |tc, i|
      puts "  #{i+1}. #{tc['name']}"
      puts "     ID: #{tc['id'].slice(0, 30)}..." if tc['id']
      puts "     Args: #{tc['arguments'].truncate(80) if tc['arguments']}"
    end
  else
    puts "\n⚠️ No tool calls in UI, but check MCP events:"
    mcp_call_events.each_with_index do |e, i|
      puts "  Event #{i+1}: name=#{e['name'] || 'nil'}, has_id=#{e['id'].present?}"
    end
  end
  
  puts "\nContent preview: #{assistant_msg.content[0..150]}..." if assistant_msg.content
end