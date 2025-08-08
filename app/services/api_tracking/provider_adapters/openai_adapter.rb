# frozen_string_literal: true

module ApiTracking
  module ProviderAdapters
    # Adapter for OpenAI API responses
    class OpenaiAdapter < BaseAdapter
      # Current OpenAI pricing as of 2024
      PRICING = {
        # GPT-4 family
        'gpt-4' => { input: 0.03, output: 0.06 },
        'gpt-4-32k' => { input: 0.06, output: 0.12 },
        'gpt-4-turbo' => { input: 0.01, output: 0.03 },
        'gpt-4-turbo-preview' => { input: 0.01, output: 0.03 },
        'gpt-4o' => { input: 0.005, output: 0.015 },
        'gpt-4o-mini' => { input: 0.00015, output: 0.0006 },
        'gpt-4.1' => { input: 0.005, output: 0.015 },        # Hypothetical
        'gpt-4.1-mini' => { input: 0.00032, output: 0.00128 }, # From earlier code
        
        # GPT-3.5 family
        'gpt-3.5-turbo' => { input: 0.0005, output: 0.0015 },
        'gpt-3.5-turbo-16k' => { input: 0.003, output: 0.004 },
        
        # Embeddings
        'text-embedding-ada-002' => { input: 0.00001, output: 0 },
        'text-embedding-3-small' => { input: 0.00002, output: 0 },
        'text-embedding-3-large' => { input: 0.00013, output: 0 },
        
        # Images
        'dall-e-2' => { 
          '256x256' => 0.016,
          '512x512' => 0.018,
          '1024x1024' => 0.020
        },
        'dall-e-3' => {
          'standard' => {
            '1024x1024' => 0.040,
            '1024x1792' => 0.080,
            '1792x1024' => 0.080
          },
          'hd' => {
            '1024x1024' => 0.080,
            '1024x1792' => 0.120,
            '1792x1024' => 0.120
          }
        },
        'gpt-image-1' => { # From earlier code
          'standard' => { '1024x1024' => 0.040 },
          'high' => { '1024x1024' => 0.080 }
        },
        
        # Audio
        'whisper-1' => { input: 0.006 }, # per minute
        'tts-1' => { output: 0.015 },    # per 1K characters
        'tts-1-hd' => { output: 0.030 }  # per 1K characters
      }.freeze
      
      def extract_usage_data(api_call, response)
        api_call.model_used = extract_model(api_call, response)
        
        # Determine the endpoint type
        endpoint = api_call.endpoint
        
        case endpoint
        when /chat\.completions/
          extract_chat_usage(api_call, response)
        when /embeddings/
          extract_embedding_usage(api_call, response)
        when /images\.(generate|edit|variations)/
          extract_image_usage(api_call, response)
        when /audio\.(transcriptions|translations)/
          extract_audio_usage(api_call, response)
        when /responses\.create/
          # Structured outputs endpoint
          extract_structured_output_usage(api_call, response)
        when /models\.(list|retrieve)/
          # Model queries have no cost
          api_call.total_cost = 0
        when /files\.(create|list|retrieve|content)/
          # File operations
          extract_file_usage(api_call, response)
        when /fine_tuning\.jobs/
          # Fine-tuning operations
          extract_fine_tuning_usage(api_call, response)
        when /batches/
          # Batch API operations
          extract_batch_usage(api_call, response)
        else
          # Unknown endpoint - try generic extraction
          extract_generic_usage(api_call, response)
        end
        
        # Calculate costs
        calculate_costs(api_call)
        
        # Store complete response
        api_call.response_data = serialize_response(response)
      end
      
      private
      
      def extract_chat_usage(api_call, response)
        usage = extract_value(response, 'usage')
        if usage
          # Handle both old and new response structures
          if usage.respond_to?(:prompt_tokens)
            # Direct method access (new gem structure)
            api_call.prompt_tokens = usage.prompt_tokens
            api_call.completion_tokens = usage.completion_tokens
            api_call.total_tokens = usage.total_tokens
          else
            # Hash-like access (old structure)
            api_call.prompt_tokens = extract_value(usage, 'prompt_tokens')
            api_call.completion_tokens = extract_value(usage, 'completion_tokens')
            api_call.total_tokens = extract_value(usage, 'total_tokens')
          end
        end
        
        # Extract model if not already set
        api_call.model_used ||= extract_value(response, 'model')
      end
      
      def extract_embedding_usage(api_call, response)
        usage = extract_value(response, 'usage')
        if usage
          # Handle both old and new response structures
          if usage.respond_to?(:prompt_tokens)
            # Direct method access (new gem structure)
            api_call.prompt_tokens = usage.prompt_tokens
            api_call.total_tokens = usage.total_tokens
          else
            # Hash-like access (old structure)
            api_call.prompt_tokens = extract_value(usage, 'prompt_tokens')
            api_call.total_tokens = extract_value(usage, 'total_tokens')
          end
        end
        
        api_call.model_used ||= extract_value(response, 'model')
      end
      
      def extract_image_usage(api_call, response)
        # Extract from request params
        params = api_call.request_params['kwargs'] || {}
        
        api_call.image_count = params[:n] || params['n'] || 1
        api_call.image_size = params[:size] || params['size'] || '1024x1024'
        api_call.image_quality = params[:quality] || params['quality'] || 'standard'
        
        # Model is in request params for images
        api_call.model_used ||= params[:model] || params['model'] || 'dall-e-2'
      end
      
      def extract_audio_usage(api_call, response)
        # Audio transcription/translation
        if api_call.endpoint.include?('transcriptions')
          # Duration might be in response
          api_call.audio_duration = extract_value(response, 'duration')
        end
        
        api_call.model_used ||= 'whisper-1'
      end
      
      def extract_structured_output_usage(api_call, response)
        # Similar to chat completions but through responses.create
        output = extract_value(response, 'output')
        if output && output.is_a?(Array)
          # Aggregate token counts from all outputs
          total_prompt = 0
          total_completion = 0
          
          output.each do |item|
            usage = extract_value(item, 'usage')
            if usage
              # Handle both old and new response structures
              if usage.respond_to?(:prompt_tokens)
                # Direct method access (new gem structure)
                total_prompt += usage.prompt_tokens.to_i
                total_completion += usage.completion_tokens.to_i
              else
                # Hash-like access (old structure)
                total_prompt += extract_value(usage, 'prompt_tokens').to_i
                total_completion += extract_value(usage, 'completion_tokens').to_i
              end
            end
          end
          
          api_call.prompt_tokens = total_prompt if total_prompt > 0
          api_call.completion_tokens = total_completion if total_completion > 0
          api_call.total_tokens = total_prompt + total_completion
        end
        
        api_call.model_used ||= extract_value(response, 'model')
      end
      
      def extract_file_usage(api_call, response)
        # File operations typically don't have token costs
        # But track the file size if available
        file_size = extract_value(response, 'bytes')
        if file_size
          api_call.metadata ||= {}
          api_call.metadata['file_size'] = file_size
        end
        
        api_call.total_cost = 0
      end
      
      def extract_fine_tuning_usage(api_call, response)
        # Fine-tuning costs are complex and billed separately
        # Track the job ID for reference
        job_id = extract_value(response, 'id')
        if job_id
          api_call.metadata ||= {}
          api_call.metadata['fine_tune_job_id'] = job_id
          api_call.metadata['status'] = extract_value(response, 'status')
        end
        
        # Fine-tuning training costs are billed separately
        api_call.total_cost = 0
      end
      
      def extract_batch_usage(api_call, response)
        # Batch API gives 50% discount
        # Track batch details
        batch_id = extract_value(response, 'id')
        if batch_id
          api_call.batch_id = batch_id
          api_call.metadata ||= {}
          api_call.metadata['batch_status'] = extract_value(response, 'status')
          api_call.metadata['batch_size'] = extract_value(response, 'request_counts.total')
        end
      end
      
      def extract_generic_usage(api_call, response)
        # Try to find usage data in common locations
        usage = extract_value(response, 'usage')
        if usage
          api_call.prompt_tokens = extract_value(usage, 'prompt_tokens')
          api_call.completion_tokens = extract_value(usage, 'completion_tokens')
          api_call.total_tokens = extract_value(usage, 'total_tokens')
        end
      end
      
      def calculate_costs(api_call)
        return unless api_call.model_used
        
        model = api_call.model_used.to_s.downcase
        
        if api_call.endpoint&.include?('images')
          calculate_image_cost(api_call, model)
        elsif api_call.endpoint&.include?('audio')
          calculate_audio_cost(api_call, model)
        elsif pricing = PRICING[model]
          calculate_token_cost(api_call, pricing)
        else
          # Unknown model - log warning
          Rails.logger.warn "[OpenaiAdapter] Unknown model for pricing: #{model}"
          api_call.total_cost = 0
        end
      end
      
      def calculate_token_cost(api_call, pricing)
        if pricing.is_a?(Hash) && pricing[:input]
          # Cost per 1K tokens
          input_cost = (api_call.prompt_tokens.to_i / 1000.0) * pricing[:input]
          output_cost = (api_call.completion_tokens.to_i / 1000.0) * pricing[:output].to_f
          
          api_call.input_cost = input_cost
          api_call.output_cost = output_cost
          api_call.total_cost = input_cost + output_cost
        else
          api_call.total_cost = 0
        end
      end
      
      def calculate_image_cost(api_call, model)
        size = api_call.image_size || '1024x1024'
        quality = api_call.image_quality || 'standard'
        count = api_call.image_count || 1
        
        # Find the price for this configuration
        price_per_image = if model.include?('dall-e-3') || model.include?('gpt-image')
          PRICING.dig(model, quality, size) || 
          PRICING.dig('dall-e-3', quality, size) || 
          0.04 # Default
        else
          PRICING.dig(model, size) || 
          PRICING.dig('dall-e-2', size) || 
          0.02 # Default
        end
        
        api_call.total_cost = price_per_image * count
      end
      
      def calculate_audio_cost(api_call, model)
        if model.include?('whisper')
          # Cost per minute
          duration_minutes = (api_call.audio_duration.to_f / 60.0)
          api_call.total_cost = duration_minutes * (PRICING.dig(model, :input) || 0.006)
        elsif model.include?('tts')
          # Cost per 1K characters - would need character count
          # For now, estimate from response size
          api_call.total_cost = 0.015 # Default estimate
        else
          api_call.total_cost = 0
        end
      end
    end
  end
end