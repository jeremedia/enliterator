# frozen_string_literal: true

module Webhooks
  module Handlers
    class FineTuningHandler < BaseHandler
      def process
        case event_type
        when 'fine_tuning.job.created'
          handle_job_created
        when 'fine_tuning.job.running'
          handle_job_running
        when 'fine_tuning.job.succeeded'
          handle_job_succeeded
        when 'fine_tuning.job.failed'
          handle_job_failed
        when 'fine_tuning.job.cancelled'
          handle_job_cancelled
        else
          log_info "Unhandled fine-tuning event type: #{event_type}"
        end
      end
      
      private
      
      def handle_job_created
        job_id = data['id']
        log_info "Fine-tuning job created: #{job_id}"
        
        # Update or create FineTuneJob record
        job = ::FineTuneJob.find_or_initialize_by(openai_job_id: job_id)
        job.update!(
          status: 'created',
          base_model: data['model'],
          openai_file_id: data['training_file'],
          hyperparameters: data['hyperparameters'],
          started_at: Time.at(data['created_at'])
        )
        
        # Update metadata
        update_metadata('job_id', job_id)
        update_metadata('model', data['model'])
        
        # Send notification
        notify_job_created(job_id)
      end
      
      def handle_job_running
        job_id = data['id']
        log_info "Fine-tuning job running: #{job_id}"
        
        job = ::FineTuneJob.find_by(openai_job_id: job_id)
        job&.update!(status: 'running')
        
        # Track start time
        update_metadata('started_at', Time.current.iso8601)
        
        # Send notification
        notify_job_running(job_id)
      end
      
      def handle_job_succeeded
        job_id = data['id']
        fine_tuned_model = data['fine_tuned_model']
        trained_tokens = data['trained_tokens']
        
        log_info "Fine-tuning job succeeded: #{job_id}"
        log_info "Fine-tuned model: #{fine_tuned_model}"
        log_info "Trained tokens: #{trained_tokens}"
        
        job = ::FineTuneJob.find_by(openai_job_id: job_id)
        if job
          job.update!(
            status: 'succeeded',
            fine_tuned_model: fine_tuned_model,
            trained_tokens: trained_tokens,
            finished_at: Time.at(data['finished_at'] || Time.current.to_i)
          )
          
          # Auto-deploy if configured
          if job.auto_deploy
            job.deploy!
            log_info "Auto-deployed model #{fine_tuned_model}"
          end
        end
        
        # Update metadata
        update_metadata('fine_tuned_model', fine_tuned_model)
        update_metadata('trained_tokens', trained_tokens)
        update_metadata('finished_at', Time.current.iso8601)
        
        # Send success notification
        notify_job_succeeded(job_id, fine_tuned_model)
      end
      
      def handle_job_failed
        job_id = data['id']
        error = data['error']
        
        log_error "Fine-tuning job failed: #{job_id}"
        log_error "Error: #{error}"
        
        job = ::FineTuneJob.find_by(openai_job_id: job_id)
        job&.update!(
          status: 'failed',
          error_message: error.is_a?(Hash) ? error['message'] : error.to_s,
          finished_at: Time.at(data['finished_at'] || Time.current.to_i)
        )
        
        # Update metadata
        update_metadata('error', error)
        update_metadata('failed_at', Time.current.iso8601)
        
        # Send failure notification
        notify_job_failed(job_id, error)
      end
      
      def handle_job_cancelled
        job_id = data['id']
        log_info "Fine-tuning job cancelled: #{job_id}"
        
        job = ::FineTuneJob.find_by(openai_job_id: job_id)
        job&.update!(
          status: 'cancelled',
          finished_at: Time.at(data['finished_at'] || Time.current.to_i)
        )
        
        # Update metadata
        update_metadata('cancelled_at', Time.current.iso8601)
        
        # Send cancellation notification
        notify_job_cancelled(job_id)
      end
      
      def deploy_model(job)
        log_info "Auto-deploying model for job #{job.job_id}"
        
        # Update OpenAI settings to use the new model
        if defined?(::OpenaiSetting)
          # Determine which model type to update based on the job metadata
          model_type = job.metadata['model_type'] || 'fine_tune'
          
          setting = ::OpenaiSetting.find_or_initialize_by(
            key: "model_#{model_type}_deployed"
          )
          
          setting.update!(
            value: job.fine_tuned_model,
            description: "Auto-deployed fine-tuned model from job #{job.job_id}",
            metadata: {
              deployed_at: Time.current.iso8601,
              job_id: job.job_id,
              trained_tokens: job.trained_tokens
            }
          )
          
          log_info "Deployed model #{job.fine_tuned_model} for #{model_type}"
        end
      end
      
      # Notification methods (can be extended to send emails, Slack messages, etc.)
      
      def notify_job_created(job_id)
        log_info "NOTIFICATION: Fine-tuning job #{job_id} has been created"
      end
      
      def notify_job_running(job_id)
        log_info "NOTIFICATION: Fine-tuning job #{job_id} is now running"
      end
      
      def notify_job_succeeded(job_id, model_name)
        log_info "NOTIFICATION: Fine-tuning job #{job_id} succeeded! Model: #{model_name}"
        
        # Could send email or Slack notification here
        # NotificationMailer.fine_tune_succeeded(job_id, model_name).deliver_later
      end
      
      def notify_job_failed(job_id, error)
        log_error "NOTIFICATION: Fine-tuning job #{job_id} failed: #{error}"
        
        # Could send email or Slack notification here
        # NotificationMailer.fine_tune_failed(job_id, error).deliver_later
      end
      
      def notify_job_cancelled(job_id)
        log_info "NOTIFICATION: Fine-tuning job #{job_id} was cancelled"
      end
    end
  end
end