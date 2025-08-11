#!/usr/bin/env ruby
# Test McpToolCall tracking

require_relative 'config/environment'

puts "Testing McpToolCall tracking..."

# Create a test McpToolCall
ekn = Ekn.first
conversation = Conversation.find_or_create_by(ekn: ekn) do |c|
  c.status = 'active'
  c.last_activity_at = Time.current
end

message = conversation.messages.create!(
  role: 'user',
  content: 'Test message for MCP tracking',
  metadata: {}
)

puts "\nCreating McpToolCall record..."
mcp_call = McpToolCall.create!(
  tool_name: 'search',
  tool_id: "mcp_test_#{SecureRandom.hex(8)}",
  arguments: { query: 'test search', top_k: 10 },
  request_data: { 
    jsonrpc: "2.0",
    method: "tools/call",
    params: { name: "search", arguments: { query: "test search" } }
  },
  message: message,
  conversation: conversation,
  ekn: ekn,
  server_label: 'enliterator',
  status: 'pending'
)

puts "Created McpToolCall ##{mcp_call.id}"

# Test the workflow
puts "\nExecuting tool..."
mcp_call.execute!
puts "Status: #{mcp_call.status}"

# Simulate completion
sleep 0.1
response_data = {
  results: [
    { id: "1", title: "Test Result", text: "This is a test result" }
  ]
}

puts "\nCompleting tool call..."
mcp_call.complete!(response_data)
puts "Status: #{mcp_call.status}"
puts "Duration: #{mcp_call.duration_ms}ms"

# Check logs
puts "\n=== Logs ==="
mcp_call.logs.each do |log|
  puts "Log: #{log.label}"
  log.log_items.each do |item|
    puts "  [#{item.status}] #{item.text}"
  end
end

puts "\n=== Summary ==="
puts "McpToolCall ##{mcp_call.id}:"
puts "  Tool: #{mcp_call.tool_name}"
puts "  Status: #{mcp_call.status}"
puts "  Duration: #{mcp_call.duration_ms}ms"
puts "  Message ID: #{mcp_call.message_id}"
puts "  Conversation ID: #{mcp_call.conversation_id}"
puts "  Response data present: #{mcp_call.response_data.present?}"

puts "\nView in admin: http://localhost:3077/admin/mcp_tool_calls"