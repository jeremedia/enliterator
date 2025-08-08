# frozen_string_literal: true

# Image generation service using OpenAI's image generation API
# Research conducted: 2025-08-07
# Sources:
#   - Rails console testing: Verified model availability and parameters
#   - Web documentation: https://platform.openai.com/docs/guides/image-generation
#   - Gem source: /Users/jeremy/.gem/ruby/3.4.4/gems/openai-0.16.0/lib/openai/resources/images.rb
class ImageGenerationService < OpenaiConfig::BaseGenerationService
    
    # Models discovered through console testing and web research
    # gpt-image-1: Newest model (GPT-4o based) - confirmed via web docs
    # dall-e-3: Previous generation - verified working in console
    # dall-e-2: Legacy but still available - verified working
    AVAILABLE_MODELS = {
      'gpt-image-1' => { 
        qualities: ['low', 'medium', 'high'],
        sizes: ['1024x1024', '1024x1536', '1536x1024', '4096x4096'],
        default_quality: 'high',
        supports_multiple: false  # Only n=1 supported
      },
      'dall-e-3' => {
        qualities: ['standard', 'hd'],
        sizes: ['1024x1024', '1792x1024', '1024x1792'],
        default_quality: 'hd',
        supports_multiple: false  # Only n=1 supported
      },
      'dall-e-2' => {
        qualities: ['standard'],
        sizes: ['256x256', '512x512', '1024x1024'],
        default_quality: 'standard',
        supports_multiple: true  # Supports n=1-10
      }
    }.freeze
    
    attr_reader :prompt, :model, :quality, :size, :n, :response_format
    
    def initialize(prompt:, model: nil, quality: nil, size: nil, n: 1, response_format: 'url')
      @prompt = prompt
      @model = select_model(model)
      @quality = select_quality(quality)
      @size = select_size(size)
      @n = validate_n(n)
      @response_format = validate_response_format(response_format)
    end
    
    protected
    
    def generate_content
      params = {
        model: @model,
        prompt: @prompt,
        quality: @quality,
        size: @size,
        n: @n,
        response_format: @response_format
      }
      
      # Remove nil values to use API defaults
      params.compact!
      
      Rails.logger.info "Generating image with params: #{params.except(:prompt)}"
      
      # Create API tracking record
      api_call = OpenaiApiCall.create!(
        service_name: self.class.name,
        endpoint: 'images.generate',
        model_used: @model,
        image_size: @size,
        image_quality: @quality,
        image_count: @n,
        request_params: params.merge(prompt: @prompt.truncate(100)),
        status: 'pending'
      )
      
      # Execute and track the API call
      response = api_call.track_execution do |call|
        OPENAI.images.generate(**params)
      end
      
      # Response structure verified through console testing
      # response.data is an array of image objects
      # Each has either .url or .b64_json depending on response_format
      response
    end
    
    def transform_result(response)
      images = response.data.map do |image_data|
        {
          url: image_data.url,
          b64_json: image_data.b64_json,
          revised_prompt: image_data.revised_prompt  # dall-e-3 returns this
        }.compact
      end
      
      {
        success: true,
        images: images,
        count: images.size,
        metadata: generation_metadata.merge(
          model_used: @model,
          quality_used: @quality,
          size_used: @size
        )
      }
    end
    
    def validate_inputs!
      raise ArgumentError, "Prompt is required" if prompt.blank?
      raise ArgumentError, "Prompt too long (max 4000 chars)" if prompt.length > 4000
    end
    
    private
    
    def select_model(requested)
      # Try to get configured model from settings
      configured = begin
        OpenaiConfig::SettingsManager.model_for(:image_generation)
      rescue => e
        Rails.logger.warn "No image generation model configured: #{e.message}"
        nil
      end
      
      # If explicitly requested, validate it exists
      if requested
        unless AVAILABLE_MODELS.key?(requested)
          raise ArgumentError, "Unknown model: #{requested}. Available: #{AVAILABLE_MODELS.keys.join(', ')}"
        end
        return requested
      end
      
      # Use configured if available and valid
      return configured if configured && AVAILABLE_MODELS.key?(configured)
      
      # Default to newest model based on web research
      'gpt-image-1'
    end
    
    def select_quality(requested)
      model_config = AVAILABLE_MODELS[@model]
      
      return model_config[:default_quality] if requested.nil?
      
      available = model_config[:qualities]
      unless available.include?(requested)
        Rails.logger.warn "Quality '#{requested}' not available for #{@model}, using #{model_config[:default_quality]}"
        return model_config[:default_quality]
      end
      
      requested
    end
    
    def select_size(requested)
      return nil if requested.nil?  # Let API use its default
      
      model_config = AVAILABLE_MODELS[@model]
      available = model_config[:sizes]
      
      unless available.include?(requested)
        raise ArgumentError, "Size '#{requested}' not available for #{@model}. Available: #{available.join(', ')}"
      end
      
      requested
    end
    
    def validate_n(value)
      model_config = AVAILABLE_MODELS[@model]
      
      # Models have different support for multiple images
      if !model_config[:supports_multiple] && value != 1
        Rails.logger.warn "Model #{@model} only supports n=1, ignoring n=#{value}"
        return 1
      end
      
      # dall-e-2 supports up to 10
      if @model == 'dall-e-2' && value > 10
        Rails.logger.warn "Model #{@model} supports max n=10, capping at 10"
        return 10
      end
      
      value
    end
    
    def validate_response_format(format)
      valid_formats = ['url', 'b64_json']
      unless valid_formats.include?(format)
        raise ArgumentError, "Invalid response_format: #{format}. Must be 'url' or 'b64_json'"
      end
      format
    end
    
    def handle_error(error)
      # Check for model availability issues (account restrictions)
      if error.message.include?('model_not_found') || error.message.include?('not available')
        Rails.logger.warn "Model #{@model} not available, trying fallback"
        
        # Try next available model
        fallback_model = case @model
                        when 'gpt-image-1' then 'dall-e-3'
                        when 'dall-e-3' then 'dall-e-2'
                        else
                          nil
                        end
        
        if fallback_model
          @model = fallback_model
          @quality = select_quality(nil)  # Reset to model defaults
          @size = nil  # Let API choose default
          
          Rails.logger.info "Retrying with fallback model: #{@model}"
          return call  # Retry with fallback
        end
      end
      
      # Check for rate limits
      if error.message.include?('rate_limit')
        Rails.logger.warn "Rate limit hit for image generation"
        return {
          success: false,
          error: 'Rate limit exceeded. Please try again in a moment.',
          error_type: 'RateLimitError',
          metadata: generation_metadata
        }
      end
      
      # Default error handling
      super
    end
    
    def generation_metadata
      super.merge(
        models_available: AVAILABLE_MODELS.keys,
        research_sources: [
          'Rails console testing (2025-08-07)',
          'Web documentation research',
          'OpenAI gem v0.16.0 source code'
        ]
      )
    end
  end