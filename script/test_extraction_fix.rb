#!/usr/bin/env ruby

puts "Testing OpenAI extraction with GPT-5 response fix..."
puts

# Test 1: Direct API call
puts "Test 1: Direct API call"
begin
  # Define response model properly
  class SimpleExtraction < OpenAI::Helpers::StructuredOutput::BaseModel
    required :term, String, doc: "Extracted term"
    required :confidence, Float, doc: "Confidence score"
  end
  
  response = OPENAI.responses.create(
    model: "gpt-5-nano",
    input: [
      { role: "system", content: "Extract the main term from the text" },
      { role: "user", content: "Ruby on Rails is a web framework" }
    ],
    text: SimpleExtraction
  )
  
  # Process response with our fix
  result = response.output
    .select { |output| output.respond_to?(:content) }
    .flat_map { |output| output.content }
    .grep_v(OpenAI::Models::Responses::ResponseOutputRefusal)
    .first
  
  if result&.parsed
    puts "✅ Direct call works! Term: #{result.parsed.term}"
  else
    puts "❌ No parsed result"
  end
rescue => e
  puts "❌ Error: #{e.message}"
end

puts

# Test 2: Through service
puts "Test 2: Through TermExtractionService"
begin
  service = Lexicon::TermExtractionService.new(
    content: "Ruby on Rails is a web application framework using MVC pattern",
    source_type: "text"
  )
  
  result = service.call
  
  if result[:success]
    data = result[:data]
    if data && data.extracted_terms.any?
      puts "✅ Service works! Found #{data.extracted_terms.count} terms:"
      data.extracted_terms.first(3).each do |term|
        puts "  - #{term.canonical_term} (#{term.confidence})"
      end
    else
      puts "⚠️ Success but no terms extracted"
    end
  else
    puts "❌ Service failed: #{result[:error]}"
  end
rescue => e
  puts "❌ Error: #{e.message}"
  puts e.backtrace.first(3)
end

puts
puts "Test complete!"