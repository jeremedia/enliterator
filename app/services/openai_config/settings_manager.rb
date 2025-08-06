# frozen_string_literal: true

module OpenaiConfig
  class SettingsManager < ApplicationService
    class << self
      def model_for(task)
        task = task.to_s
        setting = OpenaiSetting.active.find_by(key: "model_#{task}")
        setting&.value || default_model_for(task)
      end
      
      def prompt_for(service_class)
        service_name = service_class.is_a?(Class) ? service_class.name : service_class.to_s
        
        template = PromptTemplate.active.for_service(service_name).first
        return template if template
        
        # Return a default template structure if none found
        default_prompt_template_for(service_name)
      end
      
      def temperature_for(task)
        task = task.to_s
        setting = OpenaiSetting.active.find_by(key: "temperature_#{task}")
        
        if setting&.value.present?
          setting.value.to_f
        else
          default_temperature_for(task)
        end
      end
      
      def create_default_settings!
        # Create default model settings - using CURRENT 2025 models
        OpenaiSetting.set(
          'model_extraction',
          'gpt-4.1',  # Latest GPT-4.1 for best extraction accuracy
          category: 'model',
          model_type: 'extraction',
          description: 'Model for entity and term extraction (requires Structured Outputs support)'
        )
        
        OpenaiSetting.set(
          'model_answer',
          'gpt-4.1',  # Latest GPT-4.1 for high-quality answers
          category: 'model',
          model_type: 'answer',
          description: 'Model for generating conversational answers'
        )
        
        OpenaiSetting.set(
          'model_routing',
          'gpt-4.1-nano',  # Fast nano model for routing (2025)
          category: 'model',
          model_type: 'routing',
          description: 'Model for query routing and intent classification'
        )
        
        OpenaiSetting.set(
          'model_fine_tune_base',
          'gpt-4.1-mini',  # Latest mini model that supports fine-tuning (2025)
          category: 'model',
          model_type: 'fine_tune',
          description: 'Base model for fine-tuning'
        )
        
        # Create default temperature settings
        OpenaiSetting.set(
          'temperature_extraction',
          '0.0',
          category: 'temperature',
          description: 'Temperature for extraction tasks (0 for deterministic)'
        )
        
        OpenaiSetting.set(
          'temperature_answer',
          '0.7',
          category: 'temperature',
          description: 'Temperature for conversational answers'
        )
        
        OpenaiSetting.set(
          'temperature_routing',
          '0.0',
          category: 'temperature',
          description: 'Temperature for routing decisions (0 for deterministic)'
        )
        
        # Create batch API config
        OpenaiSetting.set(
          'use_batch_api',
          'true',
          category: 'config',
          description: 'Use OpenAI Batch API for bulk operations (50% cost savings)'
        )
        
        OpenaiSetting.set(
          'batch_threshold',
          '10',
          category: 'config',
          description: 'Minimum items to trigger batch API usage'
        )
        
        true
      end
      
      def use_batch_api?
        setting = OpenaiSetting.active.find_by(key: 'use_batch_api')
        setting&.value == 'true'
      end
      
      def batch_threshold
        setting = OpenaiSetting.active.find_by(key: 'batch_threshold')
        setting&.value&.to_i || 10
      end
      
      def validate_model(model_name, task_type)
        # Always allow fine-tuned models
        return true if model_name.start_with?('ft:')
        
        # Check against supported models
        supported = supported_models_for(task_type)
        supported.include?(model_name)
      end
      
      # Dynamically fetch current models from OpenAI API
      def refresh_available_models!
        Rails.cache.fetch('openai_available_models', expires_in: 24.hours) do
          begin
            models = OPENAI.models.list
            {
              all: models.data.map(&:id).sort,
              gpt: models.data.select { |m| m.id.include?('gpt') }.map(&:id).sort,
              fine_tunable: models.data.select { |m| 
                m.id.include?('gpt-3.5') || 
                m.id.include?('4.1-mini') || 
                m.id.include?('4.1-nano')
              }.map(&:id).sort,
              fetched_at: Time.current
            }
          rescue => e
            Rails.logger.error "Failed to fetch OpenAI models: #{e.message}"
            nil
          end
        end
      end
      
      # Get current available models (with caching)
      def available_models
        refresh_available_models! || { all: [], gpt: [], fine_tunable: [] }
      end
      
      def supported_models_for(task_type)
        case task_type.to_s
        when 'extraction'
          # Models that support Structured Outputs (2025 models)
          ["gpt-4.1", "gpt-4.1-2025-04-14", "gpt-4.1-mini", "gpt-4.1-mini-2025-04-14", "gpt-4o", "chatgpt-4o-latest"]
        when 'answer', 'conversation'
          # All models that can generate text (2025 models)
          ["gpt-4.1", "gpt-4.1-2025-04-14", "gpt-4.1-mini", "gpt-4.1-mini-2025-04-14", 
           "gpt-4.1-nano", "gpt-4.1-nano-2025-04-14", "gpt-4o", "gpt-4-turbo", "gpt-3.5-turbo"]
        when 'routing'
          # Fast, cheap models for routing (2025 models)
          ["gpt-4.1-nano", "gpt-4.1-nano-2025-04-14", "gpt-4.1-mini", "gpt-3.5-turbo"]
        when 'fine_tune'
          # Models that support fine-tuning (verified from API)
          ["gpt-4.1-mini", "gpt-4.1-mini-2025-04-14", "gpt-4.1-nano", "gpt-4.1-nano-2025-04-14", "gpt-3.5-turbo"]
        else
          []
        end
      end
      
      private
      
      def default_model_for(task)
        case task.to_s
        when 'extraction'
          ENV.fetch("OPENAI_MODEL", "gpt-4.1")  # Latest 2025 model
        when 'answer'
          ENV.fetch("OPENAI_MODEL_ANSWER", "gpt-4.1")  # Latest 2025 model
        when 'routing'
          ENV.fetch("OPENAI_FT_MODEL", "gpt-4.1-nano")  # Fast 2025 nano model
        when 'fine_tune', 'fine_tune_base'
          ENV.fetch("OPENAI_FT_BASE", "gpt-4.1-mini")  # 2025 mini model for fine-tuning
        else
          "gpt-4.1"  # Default to latest 2025 model
        end
      end
      
      def default_temperature_for(task)
        temps = Rails.application.config.openai[:temperature]
        
        case task.to_s
        when 'extraction'
          temps[:extraction] || 0.0
        when 'answer'
          temps[:answer] || 0.7
        when 'routing'
          temps[:routing] || 0.0
        else
          0.5
        end
      end
      
      def default_prompt_template_for(service_name)
        # Return a basic template structure that services can use
        # This allows services to work even without a database template
        OpenStruct.new(
          system_prompt: default_system_prompt_for(service_name),
          user_prompt_template: "{{content}}",
          render_user_prompt: ->(vars) { vars[:content] || vars["content"] },
          build_messages: ->(content, vars = {}) {
            [
              { role: "system", content: default_system_prompt_for(service_name) },
              { role: "user", content: content }
            ]
          }
        )
      end
      
      def default_system_prompt_for(service_name)
        case service_name
        when /TermExtraction/i
          "You are a lexicon extraction specialist. Extract canonical terms, surface forms, and descriptions from content."
        when /EntityExtraction/i
          "You are an entity extraction specialist for the Ten Pool Canon. Extract entities that belong to specific pools."
        when /RelationExtraction/i
          "You are a relationship extraction specialist. Identify relationships between entities using the Relation Verb Glossary."
        else
          "You are an AI assistant helping with the Enliterator system."
        end
      end
    end
  end
end