# API Tracking System

## Overview

The API Tracking System is a comprehensive wrapper that intercepts, logs, and caches all external API calls made by the Enliterator application. It provides full visibility into API usage, costs, and enables response caching for improved performance and reduced costs.

## Features

- **Universal API Tracking**: Tracks all API calls from OpenAI, Anthropic, Ollama, and other providers
- **Complete Response Storage**: Stores full API responses for analysis and debugging
- **Intelligent Caching**: Reduces costs by caching identical requests
- **Cost Tracking**: Calculates and tracks costs for paid APIs
- **User Attribution**: Associates API calls with users
- **Provider Adapters**: Extensible system for adding new API providers

## Architecture

### Core Components

1. **TrackedApiClient** (`app/services/api_tracking/tracked_api_client.rb`)
   - Universal wrapper that intercepts all method calls
   - Handles method chaining (e.g., `client.chat.completions.create`)
   - Manages caching and response storage

2. **Provider Adapters** (`app/services/api_tracking/provider_adapters/`)
   - `BaseAdapter`: Common functionality for all providers
   - `OpenaiAdapter`: OpenAI-specific pricing and usage extraction
   - `AnthropicAdapter`: Anthropic API support
   - `OllamaAdapter`: Local model support
   - `GenericAdapter`: Fallback for unknown providers

3. **ApiCall Models** (`app/models/api_call.rb`)
   - Base model with Single Table Inheritance (STI)
   - `OpenaiApiCall`, `AnthropicApiCall`, `OllamaApiCall` subclasses
   - Tracks: endpoint, model, tokens, cost, response data, cache keys

## Usage

### Automatic Tracking

Once configured, all API calls are automatically tracked:

```ruby
# This call is automatically tracked
response = OPENAI.chat.completions.create(
  model: "gpt-4o-mini",
  messages: [{ role: "user", content: "Hello" }]
)
```

### Viewing Tracked Calls

Access the admin interface at `/admin/api_calls` to view:
- All API calls with filtering and sorting
- Detailed view of each call including full response
- Cost breakdown and usage statistics

### Caching

Caching is automatic for identical requests:
- **Embeddings**: Cached for 1 week
- **Model lists**: Cached for 1 day  
- **Chat completions**: Cached for 1 hour
- **Default**: 30 minutes

### Adding New Providers

1. Create a new adapter in `app/services/api_tracking/provider_adapters/`:

```ruby
module ApiTracking
  module ProviderAdapters
    class YourProviderAdapter < BaseAdapter
      def extract_usage_data(api_call, response)
        # Extract tokens, model, etc.
      end
      
      def calculate_cost(api_call)
        # Calculate cost based on usage
      end
    end
  end
end
```

2. Add provider configuration in `config/initializers/z_api_tracking.rb`:

```ruby
Rails.application.config.after_initialize do
  if defined?(YOUR_CLIENT)
    ORIGINAL_YOUR_CLIENT = YOUR_CLIENT
    tracked_client = ApiTracking::TrackedApiClient.new(
      provider: 'your_provider',
      client: ORIGINAL_YOUR_CLIENT,
      cache_enabled: true
    )
    Object.const_set(:YOUR_CLIENT, tracked_client)
  end
end
```

## Configuration

Edit `config/initializers/z_api_tracking.rb` to configure:

```ruby
Rails.application.config.api_tracking = {
  enabled: true,                    # Global on/off switch
  cache_enabled: true,              # Enable response caching
  store_full_response: true,        # Store complete responses
  max_response_size: 10.megabytes, # Max response to store
  cache_durations: {                # Cache TTLs by endpoint
    embeddings: 1.week,
    models: 1.day,
    chat: 1.hour,
    default: 30.minutes
  }
}
```

## Database Schema

The `api_calls` table stores all tracked calls:

```ruby
create_table :api_calls do |t|
  t.string :type              # STI: OpenaiApiCall, etc.
  t.string :service_name      # Calling service
  t.string :endpoint          # API endpoint
  t.string :model_used        # Model name
  t.string :status            # success/error
  t.integer :prompt_tokens    # Input tokens
  t.integer :completion_tokens # Output tokens
  t.integer :total_tokens     # Total tokens
  t.decimal :total_cost       # Calculated cost
  t.string :response_cache_key # Cache key
  t.json :request_params      # Request details
  t.json :response_data       # Full response
  t.json :metadata           # Additional data
  t.integer :response_time_ms # Response time
  t.string :error_code       # Error type
  t.text :error_message      # Error details
  t.json :error_details      # Stack trace
  t.references :user         # User attribution
  t.timestamps
end
```

## Benefits

1. **Cost Reduction**: Caching eliminates duplicate API calls
2. **Performance**: Cached responses return in <10ms vs 1-2s for API calls
3. **Debugging**: Full response storage aids in troubleshooting
4. **Analytics**: Track usage patterns and optimize API usage
5. **Compliance**: Audit trail of all external API interactions
6. **Re-use**: Stored responses can be re-analyzed without new API calls

## Future Enhancements

- [ ] Rate limiting per user/service
- [ ] Budget alerts and limits
- [ ] Response compression for large payloads
- [ ] Batch API call optimization
- [ ] Webhook support for async APIs
- [ ] GraphQL API tracking
- [ ] Export to analytics platforms

## Testing

Run the test script to verify the wrapper is working:

```bash
rails runner script/test_api_tracking.rb
```

View tracked calls:

```bash
rails c
ApiCall.recent.each { |c| puts "#{c.endpoint}: #{c.total_tokens} tokens" }
```