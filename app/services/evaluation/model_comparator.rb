# frozen_string_literal: true

module Evaluation
  class ModelComparator
    attr_reader :base_model, :fine_tuned_model, :system_prompt
    
    def initialize(base_model:, fine_tuned_model:, system_prompt:)
      @base_model = base_model
      @fine_tuned_model = fine_tuned_model
      @system_prompt = system_prompt
      @client = OPENAI
    end
    
    def evaluate(user_message, temperature: 0.7, wrap_responses: true)
      return { error: "Message cannot be blank" } if user_message.blank?
      
      # Start timing
      start_time = Time.current
      
      # Call both models in parallel using threads
      base_thread = Thread.new { call_model(@base_model, user_message, temperature) }
      fine_tuned_thread = Thread.new { call_model(@fine_tuned_model, user_message, temperature) }
      
      # Wait for both to complete
      base_result = base_thread.value
      fine_tuned_result = fine_tuned_thread.value
      
      # Wrap fine-tuned response to be more literate if needed
      if wrap_responses && !fine_tuned_result[:error]
        original_content = fine_tuned_result[:content]
        wrapped_content = Evaluation::LiterateWrapper.wrap_response(original_content, user_message)
        fine_tuned_result[:content] = wrapped_content
        fine_tuned_result[:original_routing] = original_content if wrapped_content != original_content
      end
      
      # Calculate total time
      total_time = Time.current - start_time
      
      {
        base_response: format_response(base_result, 'base'),
        fine_tuned_response: format_response(fine_tuned_result, 'fine_tuned'),
        metrics: {
          total_time: total_time.round(2),
          base_time: base_result[:time_taken]&.round(2),
          fine_tuned_time: fine_tuned_result[:time_taken]&.round(2),
          base_tokens: base_result[:usage],
          fine_tuned_tokens: fine_tuned_result[:usage]
        }
      }
    rescue => e
      Rails.logger.error "ModelComparator error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      { error: "Comparison failed: #{e.message}" }
    end
    
    private
    
    def call_model(model, message, temperature)
      start = Time.current
      
      messages = build_messages(message)
      
      response = @client.chat.completions.create(
        model: model,
        messages: messages,
        temperature: temperature,
        max_tokens: 1000
      )
      
      time_taken = Time.current - start
      
      {
        content: response.choices.first.message.content,
        usage: {
          prompt_tokens: response.usage&.prompt_tokens,
          completion_tokens: response.usage&.completion_tokens,
          total_tokens: response.usage&.total_tokens
        },
        time_taken: time_taken,
        model: model
      }
    rescue => e
      Rails.logger.error "Model call failed for #{model}: #{e.message}"
      {
        error: e.message,
        model: model,
        time_taken: Time.current - start
      }
    end
    
    def build_messages(user_message)
      messages = []
      
      # Add system prompt if present
      if @system_prompt.present?
        messages << { role: 'system', content: @system_prompt }
      end
      
      # Add user message
      messages << { role: 'user', content: user_message }
      
      messages
    end
    
    def format_response(result, model_type)
      if result[:error]
        {
          content: nil,
          error: result[:error],
          model: result[:model],
          time_taken: result[:time_taken]
        }
      else
        {
          content: result[:content],
          error: nil,
          model: result[:model],
          time_taken: result[:time_taken],
          usage: result[:usage]
        }
      end
    end
  end
end