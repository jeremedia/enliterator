# Enable MCP tools for a conversation

conv_id = ARGV[0]&.to_i || Conversation.last&.id

if conv_id
  conv = Conversation.find(conv_id)
  
  # Enable MCP tools in model_config
  conv.model_config ||= {}
  conv.model_config['use_mcp_tools'] = true
  conv.save!
  
  puts "✅ MCP tools enabled for conversation #{conv.id}"
  puts "Model config: #{conv.model_config.inspect}"
  
  # Test what the controller will see
  if conv.model_configuration&.dig('use_mcp_tools')
    puts "✅ Controller will use ChatResponseWithMcpJob"
  else
    puts "❌ Controller check failed - need to fix the check"
  end
else
  puts "No conversation found"
end