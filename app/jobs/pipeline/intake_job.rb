# frozen_string_literal: true

module Pipeline
  # Stage 1: Intake - Bundle discovery and processing
  class IntakeJob < BaseJob
    queue_as :intake
    
    def perform(bundle_path, options = {})
      log_progress "Starting intake for bundle: #{bundle_path}"
      
      # Create pipeline run record
      pipeline_run = PipelineRun.create!(
        bundle_path: bundle_path,
        stage: "intake",
        started_at: Time.current,
        options: options
      )
      
      # Process the bundle
      result = Ingest::BundleProcessor.new(bundle_path, pipeline_run: pipeline_run).process
      
      # Record results
      pipeline_run.update!(
        completed_at: Time.current,
        status: "completed",
        metrics: result.metrics,
        file_count: result.files.count
      )
      
      # Queue next stage for each file
      result.files.each do |file_info|
        Pipeline::RightsTriageJob.perform_later(file_info, pipeline_run)
      end
      
      log_progress "Completed intake: #{result.files.count} files discovered"
      track_metric "intake.files_discovered", result.files.count
      track_metric "intake.duration_ms", (Time.current - pipeline_run.started_at) * 1000
      
      result
    rescue => e
      pipeline_run&.update!(
        status: "failed",
        error_message: e.message,
        completed_at: Time.current
      )
      raise
    end
  end
end