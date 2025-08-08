# frozen_string_literal: true

module ApiTracking
  module ProviderAdapters
    # Base adapter class for provider-specific API response handling
    class BaseAdapter
      # Extract usage data from the provider's response format
      def extract_usage_data(api_call, response)
        # Override in subclasses
        api_call.response_data = serialize_response(response)
      end
      
      # Calculate costs based on usage
      def calculate_costs(api_call)
        # Override in subclasses
        api_call.total_cost = 0
      end
      
      # Determine the model from the request/response
      def extract_model(api_call, response)
        # Try to extract from response
        if response.respond_to?(:model)
          response.model
        elsif response.is_a?(Hash) && response['model']
          response['model']
        else
          api_call.request_params.dig('kwargs', 'model') ||
          api_call.request_params.dig('kwargs', :model)
        end
      end
      
      protected
      
      def serialize_response(response)
        case response
        when Hash
          response
        when String
          { text: response }
        when Numeric
          { value: response }
        else
          if response.respond_to?(:to_h)
            response.to_h
          elsif response.respond_to?(:to_json)
            JSON.parse(response.to_json)
          else
            { 
              class: response.class.name,
              value: response.to_s
            }
          end
        end
      rescue => e
        {
          serialization_error: e.message,
          class: response.class.name
        }
      end
      
      # Extract nested value from response using dot notation
      # e.g., extract_value(response, 'usage.total_tokens')
      def extract_value(obj, path)
        path.split('.').reduce(obj) do |current, key|
          if current.respond_to?(key.to_sym)
            current.send(key.to_sym)
          elsif current.is_a?(Hash)
            current[key] || current[key.to_sym]
          else
            nil
          end
        end
      rescue
        nil
      end
    end
  end
end