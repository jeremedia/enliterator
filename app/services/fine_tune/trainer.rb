# frozen_string_literal: true

module FineTune
  # Service to manage OpenAI fine-tuning jobs
  # Handles uploading training data, creating fine-tune jobs, and monitoring progress
  class Trainer < ApplicationService
    DEFAULT_HYPERPARAMETERS = {
      n_epochs: "auto",
      batch_size: "auto",
      learning_rate_multiplier: "auto"
    }.freeze
    
    attr_reader :dataset_path, :base_model, :suffix, :hyperparameters, :validation_path
    
    def initialize(dataset_path:, base_model: nil, suffix: nil, hyperparameters: nil, validation_path: nil)
      @dataset_path = dataset_path
      @base_model = base_model || default_base_model_from_settings
      @suffix = suffix || "enliterator-v#{Time.current.strftime('%Y%m%d')}"
      @hyperparameters = DEFAULT_HYPERPARAMETERS.merge(hyperparameters || {})
      @validation_path = validation_path
      
      validate_inputs!
    end
    
    def call
      Rails.logger.info "Starting fine-tune training with #{base_model}"
      
      # Upload training file
      training_file_id = upload_training_file
      
      # Upload validation file if provided
      validation_file_id = upload_validation_file if validation_path
      
      # Create fine-tuning job
      job = create_fine_tune_job(training_file_id, validation_file_id)
      
      # Save job record to database
      save_job_record(job)
      
      # Return job details
      {
        success: true,
        job_id: job.id,
        status: job.status,
        model: job.model,
        created_at: Time.at(job.created_at),
        training_file: training_file_id,
        validation_file: validation_file_id,
        hyperparameters: job.hyperparameters.to_h
      }
    rescue => e
      Rails.logger.error "Fine-tune training failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      {
        success: false,
        error: e.message,
        error_type: e.class.name
      }
    end
    
    # Monitor an existing fine-tune job
    def self.check_status(job_id)
      job = OPENAI.fine_tuning.jobs.retrieve(job_id)
      
      {
        job_id: job.id,
        status: job.status,
        model: job.model,
        fine_tuned_model: job.fine_tuned_model,
        created_at: Time.at(job.created_at),
        finished_at: job.finished_at ? Time.at(job.finished_at) : nil,
        error: job[:error],  # Use raw access to avoid parsing issues
        hyperparameters: job[:hyperparameters],  # Use raw access
        result_files: job.result_files,
        trained_tokens: job.trained_tokens,
        validation_file: job.validation_file,
        training_file: job.training_file
      }
    end
    
    # List all fine-tuning jobs
    def self.list_jobs(limit: 20)
      response = OPENAI.fine_tuning.jobs.list(limit: limit)
      
      response.data.map do |job|
        {
          job_id: job.id,
          status: job.status,
          model: job.model,
          fine_tuned_model: job.fine_tuned_model,
          created_at: Time.at(job.created_at),
          finished_at: job.finished_at ? Time.at(job.finished_at) : nil
        }
      end
    end
    
    # Cancel a running fine-tune job
    def self.cancel_job(job_id)
      OPENAI.fine_tuning.jobs.cancel(job_id)
      
      {
        success: true,
        message: "Fine-tune job #{job_id} cancelled"
      }
    rescue => e
      {
        success: false,
        error: e.message
      }
    end
    
    # List events for a fine-tune job
    def self.list_events(job_id, limit: 20)
      response = OPENAI.fine_tuning.jobs.events.list(
        fine_tuning_job_id: job_id,
        limit: limit
      )
      
      response.data.map do |event|
        {
          created_at: Time.at(event.created_at),
          level: event.level,
          message: event.message,
          type: event.type
        }
      end
    end
    
    private
    
    def validate_inputs!
      raise ArgumentError, "Dataset file not found: #{dataset_path}" unless File.exist?(dataset_path)
      raise ArgumentError, "Unsupported base model: #{base_model}" unless supported_model?(base_model)
      
      if validation_path && !File.exist?(validation_path)
        raise ArgumentError, "Validation file not found: #{validation_path}"
      end
      
      # Validate JSONL format
      validate_jsonl_format(dataset_path)
      validate_jsonl_format(validation_path) if validation_path
    end
    
    def supported_model?(model)
      # Check if it's already a fine-tuned model
      return true if model.start_with?('ft:')
      
      # Check if the model is supported for fine-tuning via SettingsManager
      OpenaiConfig::SettingsManager.validate_model(model, 'fine_tune')
    end
    
    def default_base_model_from_settings
      # Get the fine-tune base model from settings (database or ENV fallback)
      OpenaiConfig::SettingsManager.model_for('fine_tune')
    end
    
    def validate_jsonl_format(filepath)
      File.foreach(filepath).with_index do |line, index|
        begin
          data = JSON.parse(line)
          
          # Validate structure for chat format
          unless data['messages'].is_a?(Array) && data['messages'].length >= 2
            raise "Invalid format at line #{index + 1}: missing or invalid messages array"
          end
          
          # Check for required roles
          roles = data['messages'].map { |m| m['role'] }
          unless roles.include?('system') || roles.include?('user')
            raise "Invalid format at line #{index + 1}: missing required message roles"
          end
        rescue JSON::ParserError => e
          raise "Invalid JSON at line #{index + 1}: #{e.message}"
        end
      end
    end
    
    def upload_training_file
      Rails.logger.info "Uploading training file: #{dataset_path}"
      
      File.open(dataset_path, 'rb') do |file|
        response = OPENAI.files.create(
          file: file,
          purpose: 'fine-tune'
        )
        
        Rails.logger.info "Training file uploaded: #{response.id}"
        response.id
      end
    end
    
    def upload_validation_file
      return nil unless validation_path
      
      Rails.logger.info "Uploading validation file: #{validation_path}"
      
      File.open(validation_path, 'rb') do |file|
        response = OPENAI.files.create(
          file: file,
          purpose: 'fine-tune'
        )
        
        Rails.logger.info "Validation file uploaded: #{response.id}"
        response.id
      end
    end
    
    def create_fine_tune_job(training_file_id, validation_file_id)
      Rails.logger.info "Creating fine-tune job with model: #{base_model}"
      
      params = {
        model: base_model,
        training_file: training_file_id,
        suffix: suffix,
        hyperparameters: hyperparameters
      }
      
      params[:validation_file] = validation_file_id if validation_file_id
      
      # Add metadata if we have batch context
      if defined?(@batch_id) && @batch_id
        params[:metadata] = {
          batch_id: @batch_id.to_s,
          created_by: 'enliterator',
          version: '1.0'
        }
      end
      
      job = OPENAI.fine_tuning.jobs.create(params)
      
      Rails.logger.info "Fine-tune job created: #{job.id} (status: #{job.status})"
      
      job
    end
    
    def save_job_record(job)
      # Save to database if FineTuneJob model exists
      if defined?(::FineTuneJob)
        ::FineTuneJob.create!(
          job_id: job.id,
          status: job.status,
          model: job.model,
          base_model: base_model,
          suffix: suffix,
          training_file: job.training_file,
          validation_file: job.validation_file,
          hyperparameters: hyperparameters,
          created_at: Time.at(job.created_at),
          metadata: {
            dataset_path: dataset_path,
            validation_path: validation_path
          }
        )
      end
    rescue => e
      Rails.logger.warn "Could not save fine-tune job to database: #{e.message}"
    end
  end
end