# frozen_string_literal: true

module OpenaiConfig
  # Base service for all OpenAI extraction tasks using the Responses API
  # Provides the correct pattern for Structured Outputs
  class BaseExtractionService < ApplicationService
    
    class ExtractionError < StandardError; end
    
    def call
      validate_inputs!
      
      messages = build_messages
      response_class = response_model_class
      
      result = call_structured_api(messages, response_class)
      
      if result
        transform_result(result)
      else
        handle_extraction_failure
      end
    rescue => e
      handle_error(e)
    end
    
    protected
    
    # Override in subclasses to define the response model
    def response_model_class
      raise NotImplementedError, "#{self.class} must define response_model_class"
    end
    
    # Override in subclasses to build the messages array
    def build_messages
      template = OpenaiConfig::SettingsManager.prompt_for(self.class)
      
      if template.respond_to?(:build_messages)
        template.build_messages(content_for_extraction, variables_for_prompt)
      else
        default_messages
      end
    end
    
    # Override in subclasses to provide content
    def content_for_extraction
      raise NotImplementedError, "#{self.class} must define content_for_extraction"
    end
    
    # Override to provide template variables
    def variables_for_prompt
      {}
    end
    
    # Override to transform the parsed result
    def transform_result(parsed_result)
      {
        success: true,
        data: parsed_result,
        metadata: extraction_metadata
      }
    end
    
    # Override to validate inputs
    def validate_inputs!
      # Implement validation logic in subclasses
    end
    
    # Override to handle extraction failures
    def handle_extraction_failure
      {
        success: false,
        error: 'No valid response from OpenAI',
        metadata: extraction_metadata
      }
    end
    
    # Override to handle errors
    def handle_error(error)
      Rails.logger.error "#{self.class} extraction failed: #{error.message}"
      Rails.logger.error error.backtrace.join("\n") if Rails.env.development?
      
      {
        success: false,
        error: error.message,
        error_type: error.class.name,
        metadata: extraction_metadata
      }
    end
    
    # Override to provide extraction metadata
    def extraction_metadata
      {
        service: self.class.name,
        model: model_for_task,
        temperature: temperature_for_task,
        timestamp: Time.current.iso8601
      }
    end
    
    private
    
    def call_structured_api(messages, response_class)
      # Create API tracking record
      request_params = {
        messages: messages.map { |m| m.except(:content).merge(content: m[:content]&.truncate(100)) },
        response_class: response_class.name
      }
      
      # GPT-5 models don't support temperature parameter
      unless model_for_task.to_s.include?('gpt-5')
        request_params[:temperature] = temperature_for_task
      end
      
      api_call = OpenaiApiCall.create!(
        service_name: self.class.name,
        endpoint: 'responses.create',
        model_used: model_for_task,
        request_params: request_params,
        trackable: trackable_object,
        session_id: session_id,
        status: 'pending'
      )
      
      # Execute and track the API call
      response = api_call.track_execution do |call|
        # GPT-5 models don't support temperature parameter
        params = {
          model: model_for_task,
          input: messages,
          text: response_class
        }
        
        # Only add temperature for non-GPT-5 models
        unless model_for_task.to_s.include?('gpt-5')
          params[:temperature] = temperature_for_task
        end
        
        OPENAI.responses.create(**params)
      end
      
      process_response(response)
    rescue => e
      log_api_error(e)
      raise ExtractionError, "OpenAI API call failed: #{e.message}"
    end
    
    def process_response(response)
      # Extract the parsed content from the response
      # GPT-5 includes ResponseReasoningItem which we need to skip
      result = response.output
        .select { |output| output.respond_to?(:content) }
        .flat_map { |output| output.content }
        .grep_v(OpenAI::Models::Responses::ResponseOutputRefusal)
        .first
        
      result&.parsed
    end
    
    def model_for_task
      # Determine task type from class name
      task = case self.class.name
             when /Term|Lexicon/i
               'extraction'
             when /Entity|Pool/i
               'extraction'
             when /Relation/i
               'extraction'
             when /Route|Intent/i
               'routing'
             else
               'extraction'
             end
      
      OpenaiConfig::SettingsManager.model_for(task)
    end
    
    def temperature_for_task
      # Extraction tasks should always use 0 for deterministic results
      task = case self.class.name
             when /Route|Intent/i
               'routing'
             else
               'extraction'
             end
      
      OpenaiConfig::SettingsManager.temperature_for(task)
    end
    
    def default_messages
      [
        {
          role: "system",
          content: default_system_prompt
        },
        {
          role: "user",
          content: content_for_extraction
        }
      ]
    end
    
    def default_system_prompt
      "You are an extraction specialist for the Enliterator system. Extract structured data from the provided content."
    end
    
    def log_api_error(error)
      Rails.logger.error "OpenAI API Error in #{self.class}:"
      Rails.logger.error "  Message: #{error.message}"
      
      if error.respond_to?(:response)
        Rails.logger.error "  Response: #{error.response}"
      end
      
      if Rails.env.development?
        Rails.logger.error "  Backtrace:"
        Rails.logger.error error.backtrace.take(10).join("\n    ")
      end
    end
    
    # Helper method to check if we should use batch API
    def use_batch_api?
      OpenaiConfig::SettingsManager.use_batch_api? && batch_eligible?
    end
    
    # Override in subclasses to determine batch eligibility
    def batch_eligible?
      false
    end
    
    # Helper to get trackable object (override in subclasses)
    def trackable_object
      nil  # Override in subclasses to return the object being processed
    end
    
    # Helper to get session ID for grouping related calls
    def session_id
      Thread.current[:api_session_id] ||= SecureRandom.uuid
    end
  end
end