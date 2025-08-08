#!/usr/bin/env ruby

service = Lexicon::TermExtractionService.new(
  content: "Test content for extraction",
  source_type: "text"
)

# Override to debug each step
class Lexicon::TermExtractionService
  def call
    validate_inputs!
    
    messages = build_messages
    response_class = response_model_class
    
    puts "Calling API with model: #{model_for_task}"
    result = call_structured_api(messages, response_class)
    puts "API result: #{result.inspect[0..200]}"
    puts "API result class: #{result.class}" if result
    
    if result
      transformed = transform_result(result)
      puts "Transformed keys: #{transformed.keys}"
      transformed
    else
      puts "No result from API"
      handle_extraction_failure
    end
  rescue => e
    puts "Error: #{e.message}"
    handle_error(e)
  end
end

final = service.call
puts "\nFinal result:"
puts "  Success: #{final[:success]}"
puts "  Keys: #{final.keys}"
puts "  Terms: #{final[:terms]&.count}"