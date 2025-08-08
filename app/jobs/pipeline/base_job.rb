# frozen_string_literal: true

module Pipeline
  # Base class for all pipeline jobs with orchestration, error handling, and logging
  # All pipeline stage jobs should inherit from this class
  #
  # CRITICAL: This class uses around_perform to wrap job execution
  # Child classes should:
  #   1. NEVER call super in their perform method
  #   2. Implement collect_stage_metrics to return a hash of metrics
  #   3. Use log_progress for all logging
  #   4. Use track_metric to record metrics
  class BaseJob < ApplicationJob
    queue_as :pipeline
    
    attr_reader :pipeline_run, :batch, :ekn
    
    # Retry configuration
    retry_on StandardError, wait: :polynomially_longer, attempts: 3
    
    # Discard jobs that fail due to record not found
    discard_on ActiveRecord::RecordNotFound
    
    # Wrap all pipeline jobs with consistent orchestration and error handling
    around_perform do |job, block|
      # The first argument should always be the pipeline_run_id
      @pipeline_run = EknPipelineRun.find(job.arguments.first)
      @batch = @pipeline_run.ingest_batch
      @ekn = @pipeline_run.ekn
      
      log_stage_start
      log_progress("Job started: #{self.class.name} for pipeline ##{@pipeline_run.id}")
      start_time = Time.current
      
      # Set EKN context for API tracking
      ApiCall.with_ekn_context(@ekn) do
        begin
          # Execute the actual job
          block.call
          
          # Calculate duration
          duration = Time.current - start_time
          
          # Collect stage-specific metrics
          metrics = collect_stage_metrics
          metrics[:duration] = duration.round(2)
          metrics[:job_id] = job.job_id if job.respond_to?(:job_id)
          
          # Validate that the stage actually did something
          validate_stage_completion(metrics)
          
          # Mark stage as complete
          @pipeline_run.mark_stage_complete!(metrics)
          
          log_stage_complete(duration, metrics)
          
        rescue => e
          log_stage_error(e)
          @pipeline_run.mark_stage_failed!(e)
          raise # Re-raise for job retry mechanisms
        end
      end
    end
    
    protected
    
    # Stage information methods
    
    def stage_name
      self.class.name.demodulize.sub('Job', '').upcase
    end
    
    def stage_number
      @pipeline_run.current_stage_number
    end
    
    # Logging methods that integrate with Loggable
    
    def log_progress(message, level: :info)
      label = "stage_#{@pipeline_run.current_stage_number}"
      
      case level
      when :debug
        @pipeline_run.log_debug(message, label: label)
      when :warn
        @pipeline_run.log_warn(message, label: label)
      when :error
        @pipeline_run.log_error(message, label: label)
      else
        @pipeline_run.log_info(message, label: label)
      end
      
      # Also log to Rails logger for debugging
      Rails.logger.send(level, "[#{stage_name}] #{message}")
    end
    
    # Track metrics that will be saved to pipeline run
    def track_metric(name, value)
      @metrics ||= {}
      @metrics[name] = value
      log_progress("Metric - #{name}: #{value}", level: :debug)
    end
    
    # Override in subclasses to return stage-specific metrics
    def collect_stage_metrics
      @metrics || {}
    end
    
    # Validate that the stage actually processed something
    def validate_stage_completion(metrics)
      # Skip validation for stages that don't process items directly
      return if self.class.name.include?("Assembly") || self.class.name.include?("Generation")
      
      # Check for common indicators that nothing was processed
      if metrics[:items_processed] == 0 && metrics[:items_completed] == 0
        # Check if there were items to process
        if @batch.ingest_items.count > 0
          raise Pipeline::InvalidDataError, "Stage #{stage_name} completed but processed 0 items! Metrics: #{metrics.to_json}"
        end
      end
      
      # Stage-specific validations
      case self.class.name
      when "Rights::TriageJob"
        if metrics[:training_eligible] == 0 && metrics[:publishable] == 0 && @batch.ingest_items.count > 0
          log_progress "⚠️ WARNING: Rights stage found no training eligible or publishable items", level: :warn
        end
      when "Lexicon::BootstrapJob"
        if metrics[:terms_extracted] == 0 && @batch.ingest_items.count > 0
          raise Pipeline::InvalidDataError, "Lexicon stage extracted 0 terms from #{@batch.ingest_items.count} items!"
        end
      end
    end
    
    # Helper methods for pipeline jobs
    
    def with_rights_check(entity)
      unless entity.provenance_and_rights.present?
        raise Pipeline::MissingRightsError, "Entity #{entity.class}##{entity.id} has no rights"
      end
      
      yield entity
    end
    
    def items_to_process
      @batch.ingest_items.where(quarantined: false)
    end
    
    def eligible_items
      @batch.ingest_items.where(training_eligible: true, quarantined: false)
    end
    
    private
    
    def log_stage_start
      Rails.logger.info "\n" + "="*80
      Rails.logger.info "🚀 Starting Stage #{stage_number}: #{stage_name}"
      Rails.logger.info "   EKN: #{@ekn.name} (ID: #{@ekn.id})"
      Rails.logger.info "   Batch: #{@batch.id}"
      Rails.logger.info "   Database: #{@ekn.neo4j_database_name}"
      Rails.logger.info "="*80
      
      @pipeline_run.log_info(
        "Starting #{stage_name} for EKN: #{@ekn.name} (Batch: #{@batch.id})",
        label: "stage_#{stage_number}"
      )
    end
    
    def log_stage_complete(duration, metrics)
      Rails.logger.info "\n" + "="*80
      Rails.logger.info "✅ Stage #{stage_number}: #{stage_name} COMPLETED"
      Rails.logger.info "   Duration: #{duration.round(2)}s"
      Rails.logger.info "   Metrics: #{metrics.to_json}"
      Rails.logger.info "="*80
    end
    
    def log_stage_error(error)
      Rails.logger.error "\n" + "="*80
      Rails.logger.error "💥 Error in Stage #{stage_number}: #{stage_name}"
      Rails.logger.error "   Error: #{error.class} - #{error.message}"
      Rails.logger.error "   Pipeline: ##{@pipeline_run.id}"
      Rails.logger.error "   Batch: ##{@batch.id}"
      Rails.logger.error "   EKN: #{@ekn.name}"
      Rails.logger.error "   Stage duration: #{(Time.current - @pipeline_run.stage_started_at).round(2)}s" if @pipeline_run.stage_started_at
      Rails.logger.error "   Backtrace: #{error.backtrace.first(5).join("\n")}"
      Rails.logger.error "="*80
      
      @pipeline_run.log_error("Exception: #{error.class} - #{error.message}", label: "errors")
      @pipeline_run.log_error("Context: Pipeline ##{@pipeline_run.id}, Batch ##{@batch.id}", label: "errors")
      
      # Check for common issues
      if error.message.include?("queue") || error.message.include?("job")
        @pipeline_run.log_error("⚠️ This appears to be a job queueing issue. Check Solid Queue workers.", label: "errors")
      elsif error.message.include?("Neo4j") || error.message.include?("database")
        @pipeline_run.log_error("⚠️ Database connection issue. Check Neo4j status.", label: "errors")
      elsif error.message.include?("OpenAI") || error.message.include?("API")
        @pipeline_run.log_error("⚠️ OpenAI API issue. Check API key and rate limits.", label: "errors")
      end
    end
  end
  
  # Custom error classes
  class MissingRightsError < StandardError; end
  class InvalidDataError < StandardError; end
  class PipelineAbortError < StandardError; end
end