#!/usr/bin/env ruby
# frozen_string_literal: true

# Demo script for the API Call Tracking System with STI
# Run with: rails runner script/demo_api_tracking.rb

puts "\n" + "="*80
puts "API CALL TRACKING SYSTEM DEMO"
puts "="*80

# 1. Create some sample API calls for different providers
puts "\n1. Creating sample API calls..."
puts "-" * 40

# OpenAI text generation call
openai_text = OpenaiApiCall.create!(
  service_name: 'Pools::EntityExtractionService',
  endpoint: 'responses.create',
  model_used: 'gpt-4.1',
  prompt_tokens: 1500,
  completion_tokens: 750,
  total_tokens: 2250,
  response_time_ms: 1234.5,
  status: 'success'
)
openai_text.calculate_costs!
openai_text.save!
puts "  ✓ OpenAI text call: $#{openai_text.total_cost.round(4)}"

# OpenAI image generation call
openai_image = OpenaiApiCall.create!(
  service_name: 'ImageGenerationService',
  endpoint: 'images.generate',
  model_used: 'gpt-image-1',
  image_size: '1024x1024',
  image_quality: 'high',
  image_count: 2,
  response_time_ms: 3456.7,
  status: 'success'
)
openai_image.calculate_costs!
openai_image.save!
puts "  ✓ OpenAI image call: $#{openai_image.total_cost.round(4)}"

# Anthropic call with caching
anthropic_call = AnthropicApiCall.create!(
  service_name: 'Lexicon::TermExtractionService',
  endpoint: 'messages.create',
  model_used: 'claude-3.5-sonnet',
  prompt_tokens: 2000,
  completion_tokens: 1000,
  total_tokens: 3000,
  cached_tokens: 500,  # 25% cached
  response_time_ms: 987.6,
  status: 'success'
)
anthropic_call.calculate_costs!
anthropic_call.save!
puts "  ✓ Anthropic call with cache: $#{anthropic_call.total_cost.round(4)}"
puts "    Cache savings: $#{anthropic_call.metadata['cache_savings'].round(4)}"

# Ollama local call (no API cost)
ollama_call = OllamaApiCall.create!(
  service_name: 'LocalExtractionService',
  endpoint: 'generate',
  model_used: 'llama3.1:70b',
  prompt_tokens: 1000,
  completion_tokens: 500,
  total_tokens: 1500,
  response_time_ms: 5432.1,
  metadata: {
    'eval_duration' => 5_000_000_000,  # 5 seconds in nanoseconds
    'prompt_eval_duration' => 432_000_000,  # 0.432 seconds
    'load_duration' => 0  # Model was already loaded
  },
  status: 'success'
)
ollama_call.calculate_costs!
ollama_call.save!
puts "  ✓ Ollama local call: $#{ollama_call.total_cost.round(4)} (compute estimate)"

# Create some failed calls
failed_call = OpenaiApiCall.create!(
  service_name: 'TestService',
  endpoint: 'test',
  model_used: 'gpt-4.1',
  status: 'rate_limited',
  error_code: 'rate_limit_exceeded',
  error_message: 'Rate limit exceeded for model gpt-4.1',
  response_time_ms: 123.4
)
puts "  ✓ Created failed call (rate limited)"

# 2. Show usage summary
puts "\n2. Usage Summary"
puts "-" * 40

summary = ApiCall.usage_summary(:today)
puts "Total calls: #{summary[:total][:count]}"
puts "Success rate: #{summary[:total][:success_rate].round(2)}%"
puts "Total cost: $#{summary[:total][:total_cost]}"
puts "Total tokens: #{summary[:total][:total_tokens]}"

puts "\nBy Provider:"
summary[:by_provider].each do |provider, stats|
  puts "  #{provider.gsub('ApiCall', '')}:"
  puts "    Calls: #{stats[:count]}"
  puts "    Cost: $#{stats[:total_cost]}"
  puts "    Avg response: #{stats[:avg_response_time]}ms"
end

# 3. Cost Analysis
puts "\n3. Cost Analysis"
puts "-" * 40

costs = ApiCallAnalytics.cost_analysis(:today)
puts "Total cost today: $#{costs[:total_cost]}"

puts "\nBy Model:"
costs[:by_model].first(5).each do |model, cost|
  puts "  #{model}: $#{cost.round(4)}"
end

puts "\nMost expensive calls:"
costs[:expensive_calls].each do |call|
  puts "  - #{call[:service]} (#{call[:model]}): $#{call[:cost]}"
end

# 4. Performance Metrics
puts "\n4. Performance Metrics"
puts "-" * 40

perf = ApiCallAnalytics.performance_metrics(:today)
puts "Average response time: #{perf[:avg_response_time]}ms"
puts "P95 response time: #{perf[:p95_response_time]}ms"
puts "P99 response time: #{perf[:p99_response_time]}ms"

puts "\nBy Provider:"
perf[:by_provider].each do |provider, avg_time|
  puts "  #{provider}: #{avg_time}ms avg"
end

# 5. Error Analysis
puts "\n5. Error Analysis"
puts "-" * 40

errors = ApiCallAnalytics.error_analysis(:today)
puts "Total errors: #{errors[:total_errors]}"
puts "Error rate: #{errors[:error_rate]}%"

if errors[:by_error_code].any?
  puts "\nError codes:"
  errors[:by_error_code].each do |code, count|
    puts "  #{code}: #{count}"
  end
end

# 6. Model Usage Report
puts "\n6. Model Usage Report"
puts "-" * 40

model_usage = ApiCallAnalytics.model_usage(:today)
model_usage.first(5).each do |model_info|
  puts "\n#{model_info[:model]} (#{model_info[:provider]}):"
  puts "  Calls: #{model_info[:calls]}"
  puts "  Cost: $#{model_info[:cost]}"
  puts "  Tokens: #{model_info[:tokens]}"
  puts "  Success rate: #{model_info[:success_rate]}%"
  puts "  Cost/1k tokens: $#{model_info[:cost_per_1k_tokens]}"
end

# 7. Demonstrate tracking in action
puts "\n7. Live Tracking Demo"
puts "-" * 40

puts "Simulating API call with tracking..."

begin
  api_call = OpenaiApiCall.create!(
    service_name: 'DemoService',
    endpoint: 'demo.endpoint',
    model_used: 'gpt-4.1-mini',
    status: 'pending'
  )
  
  # Simulate the API call with tracking
  result = api_call.track_execution do |call|
    # Simulate API delay
    sleep 0.1
    
    # Return mock response
    OpenStruct.new(
      usage: OpenStruct.new(
        prompt_tokens: 250,
        completion_tokens: 150,
        total_tokens: 400
      ),
      model: 'gpt-4.1-mini-2025-04-14',
      choices: [
        { message: { content: "Demo response" } }
      ]
    )
  end
  
  puts "  ✓ Call tracked successfully!"
  puts "    Status: #{api_call.status}"
  puts "    Tokens: #{api_call.total_tokens}"
  puts "    Cost: $#{api_call.total_cost.round(6)}"
  puts "    Response time: #{api_call.response_time_ms.round(2)}ms"
rescue => e
  puts "  ✗ Error: #{e.message}"
end

# 8. Alerts and Recommendations
puts "\n8. Alerts & Recommendations"
puts "-" * 40

alerts = ApiCallAnalytics.active_alerts(:today)
if alerts.any?
  puts "Active Alerts:"
  alerts.each do |alert|
    icon = case alert[:severity]
           when 'critical' then '🔴'
           when 'warning' then '🟡'
           else '🔵'
           end
    puts "  #{icon} #{alert[:message]} (#{alert[:value]})"
  end
else
  puts "  ✓ No active alerts"
end

recommendations = ApiCallAnalytics.generate_recommendations(:today)
if recommendations.any?
  puts "\nRecommendations:"
  recommendations.each do |rec|
    puts "  • #{rec[:message]}"
    puts "    #{rec[:details]}" if rec[:details]
  end
else
  puts "\n  ✓ No recommendations at this time"
end

# 9. Cost Forecast
puts "\n9. Cost Forecast"
puts "-" * 40

forecast = ApiCallAnalytics.cost_forecast(:today, 30)
puts "Daily average: $#{forecast[:daily_average]}"
puts "Projected monthly: $#{forecast[:projected_monthly]}"
puts "30-day projection: $#{forecast[:projected_cost]}"

# 10. Provider Comparison
puts "\n10. Provider Comparison"
puts "-" * 40

comparison = ApiCallAnalytics.provider_comparison(:today)
comparison.each do |provider_info|
  puts "\n#{provider_info[:provider]}:"
  puts "  Calls: #{provider_info[:calls]}"
  puts "  Cost: $#{provider_info[:cost]}"
  puts "  Tokens: #{provider_info[:tokens]}"
  puts "  Avg response: #{provider_info[:avg_response_time]}ms"
  puts "  Success rate: #{provider_info[:success_rate]}%"
  puts "  Models: #{provider_info[:models_used].join(', ')}"
end

# 11. Analytics Dashboard Summary
puts "\n11. Complete Dashboard"
puts "-" * 40

dashboard = ApiCallAnalytics.dashboard(:today)
puts "Dashboard generated with #{dashboard.keys.size} sections:"
dashboard.keys.each do |section|
  puts "  • #{section}"
end

# Clean up demo data (optional)
puts "\n" + "="*80
puts "Demo complete! Created #{ApiCall.count} API call records."
puts "To clean up demo data, run: ApiCall.destroy_all"
puts "="*80