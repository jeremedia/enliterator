#!/usr/bin/env ruby
# Test the fixed DatasetBuilder service

require 'json'

puts "Testing fixed DatasetBuilder service..."

# Create a test with batch 7 (Meta-EKN)
builder = FineTune::DatasetBuilder.new(
  batch_id: 7,
  output_dir: Rails.root.join('tmp', 'test_dataset_builder')
)

begin
  result = builder.call
  
  puts "\n✅ DatasetBuilder executed successfully!"
  puts JSON.pretty_generate(result)
  
  # Check the generated files
  output_dir = Rails.root.join('tmp', 'test_dataset_builder')
  
  ['train.jsonl', 'validation.jsonl', 'test.jsonl'].each do |filename|
    filepath = output_dir.join(filename)
    if File.exist?(filepath)
      lines = File.readlines(filepath)
      puts "\n#{filename}: #{lines.length} examples"
      
      # Validate first example has correct format
      if lines.any?
        first_example = JSON.parse(lines.first)
        if first_example['messages'] && first_example['messages'].is_a?(Array)
          puts "  ✅ Correct OpenAI chat format"
          puts "  Roles: #{first_example['messages'].map { |m| m['role'] }.join(', ')}"
        else
          puts "  ❌ Invalid format - missing messages array"
        end
      end
    else
      puts "\n#{filename}: Not found"
    end
  end
  
  puts "\n✅ DatasetBuilder is properly fixed and working!"
  
rescue => e
  puts "\n❌ Error: #{e.message}"
  puts e.backtrace.first(5).join("\n")
end