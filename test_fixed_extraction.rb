#!/usr/bin/env ruby
# Test the fixed tool extraction

require_relative 'config/environment'

conv = Conversation.find(17)
msg = conv.messages.create!(
  role: 'user',
  content: 'What are the first 2 Idea nodes?',
  metadata: { timestamp: Time.current, test: true }
)

puts "Running MCP job for message ##{msg.id}..."
ChatResponseWithMcpJob.perform_now(conversation_id: conv.id, message_id: msg.id)

# Check the result
assistant_msg = conv.messages.where(role: 'assistant').order(created_at: :desc).first
if assistant_msg
  puts "\n=== RESULTS ==="
  puts "Tool calls extracted: #{assistant_msg.metadata['tool_calls']&.size || 0}"
  
  if assistant_msg.metadata['tool_calls'].present? && assistant_msg.metadata['tool_calls'].any?
    puts "\n✅ SUCCESS! Tool calls:"
    assistant_msg.metadata['tool_calls'].each_with_index do |tc, i|
      puts "  #{i+1}. #{tc['name']} (#{tc['id']&.slice(0, 20)}...)"
      puts "     Args: #{tc['arguments'].truncate(100) if tc['arguments']}"
    end
  else
    puts "\n❌ No tool calls extracted"
  end
  
  puts "\nContent preview: #{assistant_msg.content[0..200]}..." if assistant_msg.content
end