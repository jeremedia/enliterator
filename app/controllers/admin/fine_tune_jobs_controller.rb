# frozen_string_literal: true

module Admin
  class FineTuneJobsController < BaseController
    before_action :set_job, only: [:show, :check_status, :deploy, :cancel]
    
    def index
      @jobs = FineTuneJob.order(created_at: :desc)
      @pending_jobs = @jobs.pending
      @completed_jobs = @jobs.completed
      @current_model = FineTuneJob.current_model
    end
    
    def show
    end
    
    def new
      @job = FineTuneJob.new
      @available_batches = IngestBatch.where.not(status: 0) # Non-pending batches
    end
    
    def create
      # This would normally create a dataset and start training
      # For now, just show a message
      redirect_to admin_fine_tune_jobs_path, 
                  notice: 'Fine-tune job creation requires FineTune::DatasetBuilder and FineTune::Trainer services (coming soon)'
    end
    
    def check_status
      @job.check_status!
      redirect_to admin_fine_tune_job_path(@job), 
                  notice: "Status updated: #{@job.status}"
    end
    
    def deploy
      if @job.deploy!
        redirect_to admin_fine_tune_jobs_path, 
                    notice: "Model #{@job.fine_tuned_model} deployed successfully"
      else
        redirect_to admin_fine_tune_job_path(@job), 
                    alert: "Cannot deploy: job not completed or model not available"
      end
    end
    
    def cancel
      @job.cancel!
      redirect_to admin_fine_tune_jobs_path, 
                  notice: "Job cancelled"
    end
    
    private
    
    def set_job
      @job = FineTuneJob.find(params[:id])
    end
  end
end