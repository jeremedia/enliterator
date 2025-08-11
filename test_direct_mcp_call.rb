#!/usr/bin/env ruby
# Direct test of MCP response structure

require_relative 'config/environment'

# Create a simple test
ekn = Ekn.find_by(slug: 'meta-enliterator')
messages = [
  { role: "system", content: "You are a helpful assistant with access to MCP tools." },
  { role: "user", content: "Search for nodes with type 'Idea'" }
]

puts "Making direct OpenAI call with MCP tools..."

begin
  response = OPENAI.responses.create(
    model: 'gpt-5',
    input: messages,
    tools: [
      {
        type: "mcp",
        server_label: "enliterator_test",
        server_url: "https://e.dev.domt.app/api/v1/mcp/sse/",
        require_approval: "never",
        allowed_tools: ["search", "fetch"]
      }
    ]
  )
  
  puts "\n=== Response Structure ==="
  puts "Response class: #{response.class.name}"
  puts "Response methods containing 'output': #{response.methods.grep(/output/).join(', ')}"
  
  if response.respond_to?(:output)
    puts "\nOutput array size: #{response.output.size}"
    
    response.output.each_with_index do |item, idx|
      puts "\n--- Output Item #{idx} ---"
      puts "Class: #{item.class.name}"
      puts "Type: #{item.type if item.respond_to?(:type)}"
      
      if item.type == 'mcp_call'
        puts "MCP Call Item!"
        
        # Get ALL instance variables
        puts "Instance variables: #{item.instance_variables.join(', ')}"
        
        # Get ALL methods (minus common Object methods)
        all_methods = item.methods - Object.new.methods
        puts "All custom methods: #{all_methods.sort.join(', ')}"
        
        # Try to access various properties (skip 'method' as it's a Ruby method)
        [:name, :tool_name, :function_name, :tool, :function, :id, :arguments, :server_label, :result, :output, :error].each do |prop|
          if item.respond_to?(prop) && prop != :method
            begin
              value = item.send(prop)
              puts "  #{prop}: #{value.inspect}" if value
            rescue => e
              puts "  #{prop}: Error - #{e.message}"
            end
          end
        end
        
        # Try instance variables directly
        item.instance_variables.each do |var|
          value = item.instance_variable_get(var)
          puts "  Instance var #{var}: #{value.inspect}"
        end
        
        # Try to convert to hash
        if item.respond_to?(:to_h)
          puts "As hash: #{item.to_h.inspect}"
        end
        
        if item.respond_to?(:to_json)
          puts "As JSON: #{item.to_json}"
        end
      end
    end
  end
  
  # Check the final text
  if response.respond_to?(:output_text)
    puts "\n=== Output Text (first 200 chars) ==="
    puts response.output_text[0..200]
  end
  
rescue => e
  puts "Error: #{e.message}"
  puts e.backtrace.first(5)
end