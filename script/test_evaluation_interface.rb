#!/usr/bin/env ruby
# Test script for the model evaluation interface

require_relative '../config/environment'

puts "Testing Model Evaluation Interface..."
puts "=" * 50

# Find a completed fine-tune job
job = FineTuneJob.completed.last

if job.nil?
  puts "❌ No completed fine-tune jobs found"
  puts "Please complete a fine-tuning job first"
  exit 1
end

puts "✅ Found completed job: #{job.openai_job_id}"
puts "   Base Model: #{job.base_model}"
puts "   Fine-Tuned Model: #{job.fine_tuned_model}"
puts ""

# Test the ModelComparator service
puts "Testing ModelComparator service..."
puts "-" * 30

comparator = Evaluation::ModelComparator.new(
  base_model: job.base_model,
  fine_tuned_model: job.fine_tuned_model,
  system_prompt: "You are an Enliterator routing assistant. Map queries to canonical terms and suggest appropriate tools."
)

test_message = "What camps were near Center Camp in 2019?"

puts "Test message: #{test_message}"
puts "Calling both models..."
puts ""

result = comparator.evaluate(test_message, temperature: 0.7)

if result[:error]
  puts "❌ Error: #{result[:error]}"
  exit 1
end

puts "Base Model Response:"
puts "-" * 20
if result[:base_response][:error]
  puts "Error: #{result[:base_response][:error]}"
else
  puts result[:base_response][:content]
  puts "\nTime: #{result[:metrics][:base_time]}s"
  puts "Tokens: #{result[:metrics][:base_tokens][:total_tokens]}" if result[:metrics][:base_tokens]
end

puts "\n" + "=" * 50 + "\n"

puts "Fine-Tuned Model Response:"
puts "-" * 20
if result[:fine_tuned_response][:error]
  puts "Error: #{result[:fine_tuned_response][:error]}"
else
  puts result[:fine_tuned_response][:content]
  puts "\nTime: #{result[:metrics][:fine_tuned_time]}s"
  puts "Tokens: #{result[:metrics][:fine_tuned_tokens][:total_tokens]}" if result[:metrics][:fine_tuned_tokens]
end

puts "\n" + "=" * 50
puts "✅ Model evaluation interface test complete!"
puts ""
puts "To test the UI:"
puts "1. Start the Rails server: bin/dev"
puts "2. Visit: http://localhost:3000/admin/fine_tune_jobs/#{job.id}"
puts "3. Click 'Evaluate Model' button"
puts "4. Try sending messages to compare responses"