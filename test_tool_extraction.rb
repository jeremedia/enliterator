#!/usr/bin/env ruby
# Test tool extraction in ChatResponseWithMcpJob

require_relative 'config/environment'

# Find or create test conversation
ekn = Ekn.find_by(slug: 'meta') || Ekn.first
unless ekn
  puts "No EKN found! Please create one first."
  exit 1
end

# Enable MCP tools for ALL conversations
Conversation.where(ekn: ekn).update_all(
  model_config: {
    model_name: OpenaiConfig::SettingsManager.model_for(:answer),
    temperature: 0.7,
    max_tokens: 2000,
    use_mcp_tools: true
  }
)

conversation = ekn.conversations.last || ekn.conversations.create!(
  status: :active,
  last_activity_at: Time.current,
  context: { started_at: Time.current },
  model_config: {
    model_name: OpenaiConfig::SettingsManager.model_for(:answer),
    temperature: 0.7,
    max_tokens: 2000,
    use_mcp_tools: true
  }
)

puts "Using conversation ##{conversation.id} with MCP tools: #{conversation.model_config['use_mcp_tools']}"

# Create test message
test_message = conversation.add_message(
  role: 'user',
  content: 'List all Idea nodes in the knowledge graph',
  metadata: { test: true, timestamp: Time.current }
)

puts "Created test message ##{test_message.id}: #{test_message.content}"
puts "\nTrigger this test with: ChatResponseWithMcpJob.perform_now(conversation_id: #{conversation.id}, message_id: #{test_message.id})"
puts "\nOr visit: http://localhost:3077/ekns/#{ekn.slug}/chat/#{conversation.id}"