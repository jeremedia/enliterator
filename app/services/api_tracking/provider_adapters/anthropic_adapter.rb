# frozen_string_literal: true

module ApiTracking
  module ProviderAdapters
    # Adapter for Anthropic Claude API responses
    class AnthropicAdapter < BaseAdapter
      # Anthropic pricing as of 2024
      PRICING = {
        # Claude 3 family
        'claude-3-opus' => { input: 0.015, output: 0.075 },
        'claude-3-sonnet' => { input: 0.003, output: 0.015 },
        'claude-3-haiku' => { input: 0.00025, output: 0.00125 },
        'claude-3.5-sonnet' => { input: 0.003, output: 0.015 },
        
        # Claude 2 family
        'claude-2.1' => { input: 0.008, output: 0.024 },
        'claude-2' => { input: 0.008, output: 0.024 },
        'claude-instant-1.2' => { input: 0.00163, output: 0.00551 },
        
        # Future models (hypothetical)
        'claude-4' => { input: 0.01, output: 0.05 }
      }.freeze
      
      # Cache discount for Anthropic's prompt caching feature
      CACHE_DISCOUNT = 0.9 # 90% discount for cached tokens
      
      def extract_usage_data(api_call, response)
        api_call.model_used = extract_model(api_call, response)
        
        # Extract usage from Anthropic's response format
        usage = extract_value(response, 'usage')
        if usage
          api_call.prompt_tokens = extract_value(usage, 'input_tokens')
          api_call.completion_tokens = extract_value(usage, 'output_tokens')
          api_call.total_tokens = (api_call.prompt_tokens.to_i + api_call.completion_tokens.to_i)
          
          # Anthropic supports caching
          cache_creation = extract_value(usage, 'cache_creation_input_tokens')
          cache_read = extract_value(usage, 'cache_read_input_tokens')
          
          if cache_creation || cache_read
            api_call.cached_tokens = (cache_creation.to_i + cache_read.to_i)
            api_call.metadata ||= {}
            api_call.metadata['cache_creation_tokens'] = cache_creation
            api_call.metadata['cache_read_tokens'] = cache_read
          end
        end
        
        # Calculate costs
        calculate_costs(api_call)
        
        # Store complete response
        api_call.response_data = serialize_response(response)
      end
      
      private
      
      def calculate_costs(api_call)
        return unless api_call.model_used
        
        model = api_call.model_used.to_s.downcase
        pricing = PRICING[model]
        
        unless pricing
          Rails.logger.warn "[AnthropicAdapter] Unknown model for pricing: #{model}"
          api_call.total_cost = 0
          return
        end
        
        # Calculate base costs
        input_tokens = api_call.prompt_tokens.to_i
        output_tokens = api_call.completion_tokens.to_i
        cached_tokens = api_call.cached_tokens.to_i
        
        # Cached tokens get a discount
        regular_input_tokens = input_tokens - cached_tokens
        cached_cost = (cached_tokens / 1000.0) * pricing[:input] * (1 - CACHE_DISCOUNT)
        regular_input_cost = (regular_input_tokens / 1000.0) * pricing[:input]
        
        api_call.input_cost = regular_input_cost + cached_cost
        api_call.output_cost = (output_tokens / 1000.0) * pricing[:output]
        api_call.total_cost = api_call.input_cost + api_call.output_cost
        
        # Track cache savings
        if cached_tokens > 0
          full_cost = (input_tokens / 1000.0) * pricing[:input] + api_call.output_cost
          api_call.metadata ||= {}
          api_call.metadata['cache_savings'] = full_cost - api_call.total_cost
          api_call.metadata['cache_discount_applied'] = true
        end
      end
    end
  end
end