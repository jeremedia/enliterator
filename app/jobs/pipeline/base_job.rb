# frozen_string_literal: true

module Pipeline
  # Base class for all pipeline jobs with error handling and logging
  class BaseJob < ApplicationJob
    queue_as :pipeline
    
    # Retry configuration
    retry_on StandardError, wait: :polynomially_longer, attempts: 3
    
    # Discard jobs that fail due to record not found
    discard_on ActiveRecord::RecordNotFound
    
    # Track job performance
    around_perform do |job, block|
      start_time = Time.current
      
      logger.info "[#{job.class.name}] Starting job #{job.job_id}"
      
      block.call
      
      duration = Time.current - start_time
      logger.info "[#{job.class.name}] Completed job #{job.job_id} in #{duration.round(2)}s"
    end
    
    # Error handling
    rescue_from(StandardError) do |exception|
      logger.error "[#{self.class.name}] Job failed: #{exception.message}"
      logger.error exception.backtrace.first(10).join("\n")
      
      # Record failure in pipeline tracking
      if arguments.first.respond_to?(:pipeline_run)
        arguments.first.pipeline_run&.record_failure(
          stage: self.class.name.demodulize.underscore,
          error: exception.message
        )
      end
      
      raise exception # Re-raise to trigger retry
    end
    
    protected
    
    # Common helper methods for pipeline jobs
    
    def with_rights_check(entity)
      unless entity.provenance_and_rights.present?
        raise Pipeline::MissingRightsError, "Entity #{entity.class}##{entity.id} has no rights"
      end
      
      yield entity
    end
    
    def log_progress(message, level: :info)
      logger.send(level, "[#{self.class.name}] #{message}")
    end
    
    def track_metric(name, value)
      # Could integrate with monitoring system
      logger.info "[METRIC] #{name}: #{value}"
    end
  end
  
  # Custom error classes
  class MissingRightsError < StandardError; end
  class InvalidDataError < StandardError; end
  class PipelineAbortError < StandardError; end
end