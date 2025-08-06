# frozen_string_literal: true

module Admin
  class FineTuneJobsController < BaseController
    before_action :set_job, only: [:show, :check_status, :deploy, :cancel, :evaluate, :evaluate_message]
    
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
    
    def evaluate
      unless @job.completed? && @job.fine_tuned_model.present?
        redirect_to admin_fine_tune_job_path(@job), 
                    alert: "Can only evaluate completed jobs with fine-tuned models"
        return
      end
      
      @base_model = @job.base_model
      @fine_tuned_model = @job.fine_tuned_model
      @system_prompt = load_system_prompt_for_job
    end
    
    def evaluate_message
      unless @job.completed? && @job.fine_tuned_model.present?
        render json: { error: "Job not ready for evaluation" }, status: :unprocessable_entity
        return
      end
      
      comparator = Evaluation::ModelComparator.new(
        base_model: @job.base_model,
        fine_tuned_model: @job.fine_tuned_model,
        system_prompt: params[:system_prompt]
      )
      
      result = comparator.evaluate(params[:message])
      
      render json: {
        base_response: result[:base_response],
        fine_tuned_response: result[:fine_tuned_response],
        metrics: result[:metrics]
      }
    rescue => e
      Rails.logger.error "Evaluation error: #{e.message}"
      render json: { error: e.message }, status: :internal_server_error
    end
    
    private
    
    def set_job
      @job = FineTuneJob.find(params[:id])
    end
    
    def load_system_prompt_for_job
      # Try to load from PromptTemplate first
      template = PromptTemplate.where(active: true).find_by(name: 'enliterator_routing')
      return template.system_prompt if template&.system_prompt.present?
      
      # Fall back to default system prompt
      "You are an Enliterator routing assistant trained on the knowledge graph. " \
      "Your role is to understand user queries, map them to canonical terms, " \
      "and suggest appropriate MCP tools to answer questions."
    end
  end
end