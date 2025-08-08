#!/usr/bin/env ruby
# Test script for EKN API tracking

puts "Testing EKN API Tracking..."
puts "=" * 50

# Get or create a test EKN
ekn = Ekn.first || Ekn.create!(name: "Test Navigator", status: "active")
puts "Using EKN: #{ekn.name} (ID: #{ekn.id})"

# Make some API calls with EKN context
ApiCall.with_ekn_context(ekn) do
  puts "Making test API call with EKN context..."
  
  response = OPENAI.chat.completions.create(
    model: "gpt-4o-mini",
    messages: [
      { role: "system", content: "You are a test assistant." },
      { role: "user", content: "Say 'EKN tracking works!' in exactly 3 words." }
    ],
    temperature: 0
  )
  
  puts "Response: #{response.choices.first.message.content}"
end

# Check if the call was tracked with EKN
recent_call = ApiCall.order(created_at: :desc).first
puts "\nLast API call:"
puts "  EKN: #{recent_call.ekn&.name || 'None'}"
puts "  EKN ID: #{recent_call.ekn_id || 'None'}"
puts "  Cost: $#{'%.6f' % (recent_call.total_cost || 0)}"

# Show EKN usage summary
if ekn.api_calls.any?
  summary = ekn.api_usage_summary
  puts "\nEKN Usage Summary:"
  puts "  Total calls: #{summary[:total_calls]}"
  puts "  Total cost: $#{'%.4f' % summary[:total_cost]}"
  puts "  Total tokens: #{summary[:total_tokens]}"
  puts "  Success rate: #{summary[:success_rate]}%"
end

# Test without EKN context
puts "\n" + "=" * 50
puts "Making call WITHOUT EKN context..."

response = OPENAI.chat.completions.create(
  model: "gpt-4o-mini",
  messages: [
    { role: "user", content: "Say 'No EKN!' in 2 words." }
  ],
  temperature: 0
)

recent_call = ApiCall.order(created_at: :desc).first
puts "Last call EKN: #{recent_call.ekn&.name || 'None (as expected)'}"

puts "\n" + "=" * 50
puts "Test complete!"