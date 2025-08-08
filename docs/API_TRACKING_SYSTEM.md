# API Call Tracking System with STI

**Created**: August 2025  
**Purpose**: Comprehensive tracking, analytics, and cost management for all LLM API calls

## Overview

The API Call Tracking System uses Single Table Inheritance (STI) to track API calls across multiple LLM providers (OpenAI, Anthropic, Ollama, etc.) with provider-specific logic while maintaining a unified interface for analytics and reporting.

## Architecture

### Database Schema

```
api_calls table
├── type (STI discriminator)
├── Common fields (service, endpoint, model, status)
├── Token tracking (prompt, completion, total, cached)
├── Cost tracking (input, output, total, currency)
├── Performance metrics (response_time_ms, retry_count)
├── Error handling (status, error_code, error_message)
└── Relationships (trackable, user)
```

### Class Hierarchy

```
ApiCall (base class)
├── OpenaiApiCall (OpenAI/GPT models)
├── AnthropicApiCall (Claude models)
├── OllamaApiCall (Local models)
└── [Extensible for other providers]
```

## Setup

### 1. Run Migration

```bash
rails db:migrate
```

This creates the `api_calls` table with all necessary fields and indexes.

### 2. Verify Models

```ruby
# In Rails console
OpenaiApiCall.new
AnthropicApiCall.new
OllamaApiCall.new
```

## Usage

### Basic Tracking

```ruby
# Manual tracking
api_call = OpenaiApiCall.create!(
  service_name: 'MyService',
  endpoint: 'chat.completions',
  model_used: 'gpt-4.1',
  status: 'pending'
)

result = api_call.track_execution do
  # Your API call here
  OPENAI.chat.completions.create(...)
end
```

### Automatic Tracking in Services

The system automatically tracks calls in:
- `BaseExtractionService` - All extraction services
- `ImageGenerationService` - Image generation

Example:
```ruby
service = Pools::EntityExtractionService.new(content: "text")
result = service.call
# API call is automatically tracked!
```

### Quick Tracking

```ruby
result = OpenaiApiCall.track(
  service: 'QuickService',
  endpoint: 'embeddings.create',
  model: 'text-embedding-3-small'
) do
  OPENAI.embeddings.create(input: "text")
end
```

## Analytics

### Dashboard

```ruby
# Complete analytics dashboard
dashboard = ApiCallAnalytics.dashboard(:today)
# Returns comprehensive metrics including:
# - Summary statistics
# - Provider comparison
# - Cost analysis
# - Performance metrics
# - Error analysis
# - Trends
# - Active alerts
# - Recommendations
```

### Cost Analysis

```ruby
# Detailed cost breakdown
costs = ApiCallAnalytics.cost_analysis(:month)
puts "Total: $#{costs[:total_cost]}"
puts "By Model: #{costs[:by_model]}"
puts "By Day: #{costs[:by_day]}"

# Cost forecast
forecast = ApiCallAnalytics.cost_forecast(:month, days_ahead: 30)
puts "Projected monthly: $#{forecast[:projected_monthly]}"
```

### Performance Metrics

```ruby
# Performance analysis
perf = ApiCallAnalytics.performance_metrics(:today)
puts "Avg response: #{perf[:avg_response_time]}ms"
puts "P95: #{perf[:p95_response_time]}ms"
puts "P99: #{perf[:p99_response_time]}ms"
```

### Error Analysis

```ruby
# Error tracking
errors = ApiCallAnalytics.error_analysis(:today)
puts "Error rate: #{errors[:error_rate]}%"
puts "By code: #{errors[:by_error_code]}"
puts "Rate limits: #{errors[:rate_limits]}"
```

### Model Usage

```ruby
# Model-specific analytics
ApiCallAnalytics.model_usage(:month).each do |model|
  puts "#{model[:model]}: #{model[:calls]} calls, $#{model[:cost]}"
  puts "  Cost/1k tokens: $#{model[:cost_per_1k_tokens]}"
end
```

## Provider-Specific Features

### OpenAI

```ruby
# Supports all OpenAI endpoints
call = OpenaiApiCall.new
call.supports_streaming?  # => true
call.supports_vision?     # => true
call.supports_functions?  # => true

# Automatic pricing for:
# - Text models (GPT-4.1 family)
# - Image models (gpt-image-1, DALL-E)
# - Embeddings
# - Audio (Whisper, TTS)

# Rate limit detection
call.approaching_rate_limit?  # => true/false
```

### Anthropic

```ruby
# Claude-specific features
call = AnthropicApiCall.new
call.supports_caching?  # => true

# Cache analytics
AnthropicApiCall.cache_analytics(:today)
# => { cache_hit_rate: 25.5, total_cache_savings: 12.50, ... }

# Cache effectiveness
call.cache_hit_rate         # => 25.0 (%)
call.cache_savings_percentage  # => 15.5 (%)
```

### Ollama (Local)

```ruby
# Local model tracking
call = OllamaApiCall.new
call.calculate_costs!  # Estimates compute costs

# Performance metrics
call.tokens_per_second        # => 42.5
call.prompt_tokens_per_second # => 150.2
call.model_load_time_ms      # => 1234.5

# Resource usage
OllamaApiCall.resource_usage(:today)
# => { total_gpu_time_ms: 123456, estimated_vram_usage: {...} }
```

## Querying

### Scopes

```ruby
# Time-based
ApiCall.today
ApiCall.yesterday
ApiCall.this_week
ApiCall.this_month

# Status
ApiCall.successful
ApiCall.failed

# Filters
ApiCall.by_model('gpt-4.1')
ApiCall.by_service('EntityExtractionService')
ApiCall.expensive  # Calls over $0.10

# Provider-specific
OpenaiApiCall.where(model_used: 'gpt-4.1')
AnthropicApiCall.where('cached_tokens > 0')
```

### Complex Queries

```ruby
# Find expensive failed calls today
ApiCall
  .today
  .failed
  .where('total_cost > ?', 0.10)
  .order(total_cost: :desc)

# Find slow OpenAI calls
OpenaiApiCall
  .where('response_time_ms > ?', 5000)
  .group(:model_used)
  .count
```

## Monitoring & Alerts

### Active Alerts

```ruby
alerts = ApiCallAnalytics.active_alerts(:today)
# Automatic alerts for:
# - High costs (>$100/day)
# - High error rate (>10%)
# - Rate limiting
# - Slow responses (>5s)
```

### Recommendations

```ruby
recs = ApiCallAnalytics.generate_recommendations(:week)
# Suggests:
# - Model optimization (use cheaper models)
# - Caching opportunities
# - Error reduction strategies
# - Performance improvements
```

## Caching Support

```ruby
# Check for cached response
cached = ApiCall.find_cached_response(
  endpoint: 'embeddings.create',
  model: 'text-embedding-3-small',
  params: { input: "test" }
)

if cached
  # Use cached response
  return cached.response_data
end
```

## Testing

Run the test suite:

```bash
# Run all API tracking tests
rails test test/models/api_call_test.rb
rails test test/models/openai_api_call_test.rb
rails test test/models/anthropic_api_call_test.rb
rails test test/models/ollama_api_call_test.rb
```

## Demo

Run the interactive demo:

```bash
rails runner script/demo_api_tracking.rb
```

This demonstrates:
- Creating API calls for different providers
- Cost calculation
- Analytics dashboard
- Performance metrics
- Error tracking
- Provider comparison
- Forecasting

## Extending the System

### Adding a New Provider

1. Create a new model:

```ruby
class NewProviderApiCall < ApiCall
  PRICING = { 
    'model-name' => { input: 1.00, output: 2.00 }
  }
  
  def calculate_costs!
    # Provider-specific cost calculation
  end
  
  def extract_usage_data(result)
    # Provider-specific usage extraction
  end
end
```

2. Add to analytics if needed:

```ruby
# In ApiCallAnalytics
providers = %w[OpenaiApiCall AnthropicApiCall OllamaApiCall NewProviderApiCall]
```

### Custom Analytics

```ruby
# Add custom analytics methods
class ApiCallAnalytics
  def self.custom_metric(period = :month)
    scope = period_scope(period)
    # Your custom analysis
  end
end
```

## Best Practices

1. **Always track API calls** - Use the tracking system for all LLM API calls
2. **Monitor costs daily** - Check the dashboard regularly
3. **Set up alerts** - Configure alerts for cost thresholds
4. **Review recommendations** - Act on optimization suggestions
5. **Use caching** - Implement caching for repeated requests
6. **Handle errors gracefully** - The system tracks all error types
7. **Analyze trends** - Use trend analysis to optimize usage

## Troubleshooting

### Missing costs

```ruby
# Recalculate costs for all calls
ApiCall.find_each do |call|
  call.calculate_costs!
  call.save!
end
```

### Performance issues

```ruby
# Add missing indexes if needed
add_index :api_calls, [:created_at, :type, :model_used]
```

### Data cleanup

```ruby
# Remove old data
ApiCall.where('created_at < ?', 3.months.ago).destroy_all
```

## Pricing Updates

When provider pricing changes:

1. Update the PRICING constant in the provider model
2. Optionally recalculate historical costs:

```ruby
OpenaiApiCall.where(model_used: 'gpt-4.1').find_each do |call|
  call.calculate_costs!
  call.save!
end
```

## Security Considerations

- Request params are truncated (first 100 chars) to avoid storing sensitive data
- Response data can be filtered before storage
- User association allows for access control
- All data is encrypted at rest (if configured in Rails)

## Performance Optimization

The system includes numerous indexes for fast queries:
- By type (STI)
- By service_name
- By model_used
- By status
- By created_at
- Composite indexes for common query patterns

## Conclusion

The API Call Tracking System provides:
- **Complete visibility** into LLM API usage
- **Cost control** through detailed tracking
- **Performance monitoring** with percentile metrics
- **Error tracking** with detailed diagnostics
- **Provider flexibility** through STI
- **Actionable insights** via recommendations
- **Future-proof architecture** for new providers

Use it to optimize your LLM usage, reduce costs, and improve reliability!