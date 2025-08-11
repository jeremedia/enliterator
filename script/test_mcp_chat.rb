# Test MCP Chat Integration
#
# This script tests the MCP tools integration with the chat interface
#

ekn = Ekn.find_by(slug: 'meta-enliterator')
puts "Using EKN: #{ekn.name}"

# Create and save a conversation
conversation = ekn.conversations.create!(
  model_config: { 'use_mcp_tools' => true },
  expertise_level: 'intermediate'
)

# Add a user message
message = conversation.messages.create!(
  role: 'user',
  content: 'What are the main components of the Enliterator architecture?'
)

puts "Created conversation #{conversation.id} with message #{message.id}"
puts ""
puts "Testing MCP integration..."

# Actually run the job
begin
  job = ChatResponseWithMcpJob.new
  job.perform(conversation_id: conversation.id, message_id: message.id)
  
  # Reload to see the response
  conversation.reload
  assistant_message = conversation.messages.where(role: 'assistant').last
  
  if assistant_message
    puts ""
    puts "AI Response:"
    puts "-" * 60
    puts assistant_message.content[0..1000]
    puts ""
    
    if assistant_message.metadata['tool_calls'] && assistant_message.metadata['tool_calls'].any?
      puts "Tools used:"
      assistant_message.metadata['tool_calls'].each do |tc|
        puts "  - #{tc['name']}: #{tc['arguments']}"
      end
    end
  end
rescue => e
  puts "Error: #{e.message}"
  puts e.backtrace.first(5).join("\n")
end