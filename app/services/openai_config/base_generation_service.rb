# frozen_string_literal: true

module OpenaiConfig
  # Base service for OpenAI generation tasks (images, audio, etc.)
  # Different from extraction - no structured outputs
  class BaseGenerationService < ApplicationService
    
    class GenerationError < StandardError; end
    
    def call
      validate_inputs!
      
      result = generate_content
      
      if result
        transform_result(result)
      else
        handle_generation_failure
      end
    rescue => e
      handle_error(e)
    end
    
    protected
    
    # Override in subclasses to implement generation
    def generate_content
      raise NotImplementedError, "#{self.class} must implement generate_content"
    end
    
    # Override to validate inputs
    def validate_inputs!
      # Implement in subclasses
    end
    
    # Override to transform result
    def transform_result(result)
      {
        success: true,
        data: result,
        metadata: generation_metadata
      }
    end
    
    def handle_generation_failure
      {
        success: false,
        error: 'Generation failed',
        metadata: generation_metadata
      }
    end
    
    def handle_error(error)
      Rails.logger.error "#{self.class} generation failed: #{error.message}"
      
      {
        success: false,
        error: error.message,
        error_type: error.class.name,
        metadata: generation_metadata
      }
    end
    
    def generation_metadata
      {
        service: self.class.name,
        timestamp: Time.current.iso8601
      }
    end
  end
end