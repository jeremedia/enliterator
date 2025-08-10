# frozen_string_literal: true

module FineTune
  # Job to deploy a fine-tuned model to production settings
  class DeploymentJob < ApplicationJob
    queue_as :default
    
    def perform(fine_tune_job_id = nil)
      # Get the most recent successful fine-tune job if not specified
      job = if fine_tune_job_id
        FineTuneJob.find(fine_tune_job_id)
      else
        FineTuneJob.completed.order(finished_at: :desc).first
      end
      
      unless job&.completed? && job.fine_tuned_model.present?
        Rails.logger.error "No completed fine-tune job found to deploy"
        return false
      end
      
      Rails.logger.info "Deploying fine-tuned model: #{job.fine_tuned_model}"
      
      # Update the routing model setting
      OpenaiSetting.set(
        'model_routing',
        job.fine_tuned_model,
        category: 'model',
        model_type: 'routing',
        description: "Fine-tuned router for intent classification and query normalization (deployed #{Time.current})"
      )
      
      
      # Log the deployment
      Rails.logger.info "Successfully deployed #{job.fine_tuned_model} as routing model"
      
      # Update the job record
      job.update!(
        dataset_path: "deployed_at_#{Time.current.iso8601}"
      )
      
      true
    end
  end
end