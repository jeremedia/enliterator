# frozen_string_literal: true

module ApiTracking
  module ProviderAdapters
    # Adapter for Ollama (local model) API responses
    class OllamaAdapter < BaseAdapter
      # Ollama runs locally, so we track compute costs instead of API costs
      # These are estimates based on typical cloud GPU costs
      COMPUTE_COSTS = {
        # Cost per hour of compute (estimated)
        'small' => 0.10,   # Models < 7B params
        'medium' => 0.50,  # Models 7B-30B params  
        'large' => 2.00,   # Models 30B-70B params
        'xlarge' => 5.00   # Models > 70B params
      }.freeze
      
      # Model size classifications
      MODEL_SIZES = {
        'llama3.1:8b' => 'small',
        'llama3.1:70b' => 'large',
        'llama3.1:405b' => 'xlarge',
        'llama2:7b' => 'small',
        'llama2:13b' => 'medium',
        'llama2:70b' => 'large',
        'mistral:7b' => 'small',
        'mixtral:8x7b' => 'medium',
        'codellama:7b' => 'small',
        'codellama:34b' => 'medium',
        'phi3' => 'small',
        'gemma:2b' => 'small',
        'gemma:7b' => 'small'
      }.freeze
      
      def extract_usage_data(api_call, response)
        api_call.model_used = extract_model(api_call, response)
        
        # Ollama provides timing information
        if response.is_a?(Hash)
          # Extract token counts
          api_call.prompt_tokens = extract_value(response, 'prompt_eval_count')
          api_call.completion_tokens = extract_value(response, 'eval_count')
          api_call.total_tokens = (api_call.prompt_tokens.to_i + api_call.completion_tokens.to_i)
          
          # Extract timing information (in nanoseconds)
          prompt_eval_duration = extract_value(response, 'prompt_eval_duration')
          eval_duration = extract_value(response, 'eval_duration')
          load_duration = extract_value(response, 'load_duration')
          total_duration = extract_value(response, 'total_duration')
          
          # Convert to milliseconds and store
          if total_duration
            api_call.response_time_ms = total_duration.to_f / 1_000_000
          end
          
          # Store detailed metrics
          api_call.metadata ||= {}
          api_call.metadata['prompt_eval_duration_ms'] = prompt_eval_duration.to_f / 1_000_000 if prompt_eval_duration
          api_call.metadata['eval_duration_ms'] = eval_duration.to_f / 1_000_000 if eval_duration
          api_call.metadata['load_duration_ms'] = load_duration.to_f / 1_000_000 if load_duration
          
          # Calculate tokens per second
          if eval_duration && api_call.completion_tokens
            tokens_per_second = api_call.completion_tokens.to_f / (eval_duration.to_f / 1_000_000_000)
            api_call.metadata['tokens_per_second'] = tokens_per_second.round(2)
          end
          
          if prompt_eval_duration && api_call.prompt_tokens
            prompt_tokens_per_second = api_call.prompt_tokens.to_f / (prompt_eval_duration.to_f / 1_000_000_000)
            api_call.metadata['prompt_tokens_per_second'] = prompt_tokens_per_second.round(2)
          end
        end
        
        # Calculate compute costs
        calculate_costs(api_call)
        
        # Store complete response
        api_call.response_data = serialize_response(response)
      end
      
      private
      
      def calculate_costs(api_call)
        # For local models, estimate compute cost based on time
        model = api_call.model_used.to_s.downcase
        
        # Determine model size
        model_size = determine_model_size(model)
        hourly_cost = COMPUTE_COSTS[model_size]
        
        # Calculate cost based on response time
        if api_call.response_time_ms
          hours_used = api_call.response_time_ms.to_f / (1000 * 60 * 60)
          api_call.total_cost = hours_used * hourly_cost
        else
          # No timing info, estimate based on tokens
          # Rough estimate: 100 tokens/second for small models
          estimated_seconds = api_call.total_tokens.to_f / 100
          hours_used = estimated_seconds / 3600
          api_call.total_cost = hours_used * hourly_cost
        end
        
        # Round to reasonable precision
        api_call.total_cost = api_call.total_cost.round(8)
        
        # Mark as local/compute cost
        api_call.metadata ||= {}
        api_call.metadata['cost_type'] = 'compute_estimate'
        api_call.metadata['model_size'] = model_size
        api_call.metadata['hourly_rate'] = hourly_cost
      end
      
      def determine_model_size(model)
        # Check known models
        MODEL_SIZES.each do |model_pattern, size|
          return size if model.include?(model_pattern)
        end
        
        # Guess based on parameter count in model name
        case model
        when /\d+b/i
          params = model.match(/(\d+)b/i)[1].to_i
          if params < 10
            'small'
          elsif params < 30
            'medium'
          elsif params < 100
            'large'
          else
            'xlarge'
          end
        else
          # Default to small for unknown models
          'small'
        end
      end
    end
  end
end