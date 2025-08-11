# Simple MCP Test - Direct API call
#
# This script tests the MCP tools integration directly with OpenAI's Responses API
#

puts "Testing MCP tools with OpenAI Responses API..."
puts "=" * 60

begin
  response = OPENAI.responses.create(
    model: 'gpt-5-mini',
    input: [
      {
        role: 'system',
        content: 'You are a helpful assistant with access to the Enliterator knowledge graph. Use the available tools to search for information.'
      },
      {
        role: 'user',
        content: 'Search the knowledge graph for information about the Ten Pool Canon and explain what it is.'
      }
    ],
    tools: [{
      type: 'mcp',
      server_label: 'enliterator',
      server_url: 'https://e.dev.domt.app/api/v1/mcp/sse/',
      require_approval: 'never',
      headers: {
        'Authorization': 'Bearer test-key-123'
      }
    }]
  )
  
  puts "\n✅ SUCCESS! MCP tools integration works!\n"
  puts "-" * 60
  
  # Show what happened
  tool_calls = 0
  response.output.each do |output|
    case output.type
    when 'mcp_list_tools'
      if output.respond_to?(:tools)
        tools = output.tools.map(&:name).join(', ')
        puts "📋 Tools imported: #{tools}"
      end
    when 'mcp_call'
      tool_calls += 1
      puts "\n🔧 Tool call ##{tool_calls}: #{output.name}"
      if output.arguments
        args = JSON.parse(output.arguments) rescue output.arguments
        puts "   Args: #{args.inspect[0..100]}..."
      end
      if output.output
        begin
          result = JSON.parse(output.output)
          if result['results']
            puts "   Found #{result['results'].size} results"
          else
            puts "   Output: #{output.output[0..100]}..."
          end
        rescue
          puts "   Output: #{output.output[0..100]}..."
        end
      end
    end
  end
  
  # Show the final response
  puts "\n" + "=" * 60
  puts "📝 FINAL RESPONSE:"
  puts "-" * 60
  if response.respond_to?(:output_text) && response.output_text
    puts response.output_text
  else
    # Fallback to looking for message output
    response.output.each do |output|
      if output.type == 'message' && output.respond_to?(:content)
        puts output.content
        break
      end
    end
  end
  
rescue => e
  puts "\n❌ Error: #{e.message}"
  puts e.backtrace.first(5).join("\n")
end