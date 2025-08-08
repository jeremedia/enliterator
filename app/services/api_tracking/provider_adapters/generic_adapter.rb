# frozen_string_literal: true

module ApiTracking
  module ProviderAdapters
    # Generic adapter for unknown/future API providers
    class GenericAdapter < BaseAdapter
      def extract_usage_data(api_call, response)
        api_call.model_used = extract_model(api_call, response)
        
        # Try common patterns for usage data
        extract_common_usage_patterns(api_call, response)
        
        # Store complete response
        api_call.response_data = serialize_response(response)
        
        # Mark as generic provider
        api_call.metadata ||= {}
        api_call.metadata['provider_type'] = 'generic'
        api_call.metadata['requires_manual_cost'] = true
        
        # Set cost to 0 - can be manually updated later
        api_call.total_cost = 0
      end
      
      private
      
      def extract_common_usage_patterns(api_call, response)
        # Try various common patterns for token/usage data
        
        # Pattern 1: response.usage.tokens
        if usage = extract_value(response, 'usage')
          api_call.prompt_tokens = extract_value(usage, 'prompt_tokens') ||
                                   extract_value(usage, 'input_tokens') ||
                                   extract_value(usage, 'prompt')
          
          api_call.completion_tokens = extract_value(usage, 'completion_tokens') ||
                                       extract_value(usage, 'output_tokens') ||
                                       extract_value(usage, 'completion')
          
          api_call.total_tokens = extract_value(usage, 'total_tokens') ||
                                  extract_value(usage, 'total') ||
                                  (api_call.prompt_tokens.to_i + api_call.completion_tokens.to_i)
        end
        
        # Pattern 2: Direct token fields
        api_call.prompt_tokens ||= extract_value(response, 'prompt_tokens')
        api_call.completion_tokens ||= extract_value(response, 'completion_tokens')
        api_call.total_tokens ||= extract_value(response, 'total_tokens')
        
        # Pattern 3: Metrics/stats object
        if metrics = extract_value(response, 'metrics') || extract_value(response, 'stats')
          api_call.prompt_tokens ||= extract_value(metrics, 'input_tokens')
          api_call.completion_tokens ||= extract_value(metrics, 'output_tokens')
          api_call.response_time_ms ||= extract_value(metrics, 'latency') ||
                                        extract_value(metrics, 'response_time')
        end
        
        # Extract any timing information
        api_call.response_time_ms ||= extract_value(response, 'response_time') ||
                                      extract_value(response, 'latency') ||
                                      extract_value(response, 'duration')
        
        # Store any unrecognized fields in metadata for analysis
        if response.is_a?(Hash)
          unrecognized_fields = response.keys - ['usage', 'model', 'id', 'object', 'created', 'choices']
          if unrecognized_fields.any?
            api_call.metadata ||= {}
            api_call.metadata['unrecognized_fields'] = unrecognized_fields
          end
        end
      end
    end
  end
end