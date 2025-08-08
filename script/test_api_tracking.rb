#!/usr/bin/env ruby
# Test script for API tracking wrapper

puts "Testing API Tracking Wrapper..."
puts "=" * 50

# Test 1: Check if OPENAI is wrapped
puts "\n1. Checking if OPENAI is wrapped:"
puts "   OPENAI class: #{OPENAI.class}"
puts "   Is TrackedApiClient? #{OPENAI.is_a?(ApiTracking::TrackedApiClient)}"

# Test 2: Test a simple API call
puts "\n2. Testing model list (should be tracked):"
begin
  initial_count = ApiCall.count
  
  # Make a simple API call
  models = OPENAI.models.list
  
  final_count = ApiCall.count
  
  puts "   API calls before: #{initial_count}"
  puts "   API calls after: #{final_count}"
  puts "   New calls tracked: #{final_count - initial_count}"
  
  if final_count > initial_count
    last_call = ApiCall.last
    puts "   Last call endpoint: #{last_call.endpoint}"
    puts "   Last call status: #{last_call.status}"
    puts "   Response cached: #{last_call.response_cache_key.present?}"
  end
rescue => e
  puts "   Error: #{e.message}"
end

# Test 3: Test chat completion (the most common use case)
puts "\n3. Testing chat completion (should be tracked):"
begin
  initial_count = ApiCall.count
  
  response = OPENAI.chat.completions.create(
    model: "gpt-4o-mini",
    messages: [
      { role: "system", content: "You are a helpful assistant." },
      { role: "user", content: "Say 'Hello, tracking works!' in exactly 3 words." }
    ],
    temperature: 0
  )
  
  final_count = ApiCall.count
  
  puts "   API calls before: #{initial_count}"
  puts "   API calls after: #{final_count}"
  puts "   New calls tracked: #{final_count - initial_count}"
  
  if final_count > initial_count
    last_call = ApiCall.last
    puts "   Last call endpoint: #{last_call.endpoint}"
    puts "   Last call status: #{last_call.status}"
    puts "   Model used: #{last_call.model_used}"
    puts "   Tokens used: #{last_call.total_tokens}"
    puts "   Cost: $#{'%.6f' % last_call.total_cost}" if last_call.total_cost
    puts "   Response stored: #{last_call.response_data.present?}"
  end
  
  puts "   AI response: #{response.choices.first.message.content}" if response
rescue => e
  puts "   Error: #{e.message}"
  puts "   Backtrace: #{e.backtrace.first(3).join("\n             ")}"
end

# Test 4: Test caching
puts "\n4. Testing response caching:"
begin
  # Make the same call twice
  test_messages = [
    { role: "system", content: "You are a test bot." },
    { role: "user", content: "Respond with exactly: CACHE_TEST_123" }
  ]
  
  puts "   Making first call..."
  start1 = Time.now
  response1 = OPENAI.chat.completions.create(
    model: "gpt-4o-mini",
    messages: test_messages,
    temperature: 0
  )
  time1 = Time.now - start1
  
  puts "   Making identical second call..."
  start2 = Time.now
  response2 = OPENAI.chat.completions.create(
    model: "gpt-4o-mini",
    messages: test_messages,
    temperature: 0
  )
  time2 = Time.now - start2
  
  puts "   First call time: #{time1.round(3)}s"
  puts "   Second call time: #{time2.round(3)}s"
  puts "   Cache hit? #{time2 < time1 * 0.1 ? 'YES' : 'NO'}"
  
  # Check if responses match
  if response1 && response2
    content1 = response1.choices.first.message.content
    content2 = response2.choices.first.message.content
    puts "   Responses match? #{content1 == content2 ? 'YES' : 'NO'}"
  end
rescue => e
  puts "   Error: #{e.message}"
end

# Test 5: Check all tracked calls
puts "\n5. Summary of tracked API calls:"
recent_calls = ApiCall.where('created_at > ?', 5.minutes.ago).order(created_at: :desc)
puts "   Total calls in last 5 min: #{recent_calls.count}"
puts "   Unique endpoints used:"
recent_calls.pluck(:endpoint).uniq.each do |endpoint|
  count = recent_calls.where(endpoint: endpoint).count
  puts "     - #{endpoint}: #{count} call(s)"
end

puts "\n" + "=" * 50
puts "Testing complete!"