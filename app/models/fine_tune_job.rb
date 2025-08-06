# frozen_string_literal: true

class FineTuneJob < ApplicationRecord
  STATUSES = %w[validating_files queued running succeeded failed cancelled].freeze
  
  belongs_to :ingest_batch, optional: true
  
  validates :openai_job_id, presence: true, uniqueness: true
  validates :base_model, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  
  scope :pending, -> { where(status: %w[validating_files queued running]) }
  scope :completed, -> { where(status: 'succeeded') }
  scope :failed, -> { where(status: 'failed') }
  scope :with_model, -> { where.not(fine_tuned_model: nil) }
  
  def self.current_model
    completed.with_model.order(finished_at: :desc).first&.fine_tuned_model
  end
  
  def self.create_from_openai!(job_response, dataset_path: nil, batch: nil)
    create!(
      openai_job_id: job_response.id,
      openai_file_id: job_response.training_file,
      base_model: job_response.model,
      status: job_response.status,
      hyperparameters: job_response.hyperparameters&.to_h || {},
      dataset_path: dataset_path,
      ingest_batch: batch,
      started_at: Time.current
    )
  end
  
  def pending?
    status.in?(%w[validating_files queued running])
  end
  
  def completed?
    status == 'succeeded'
  end
  
  def failed?
    status == 'failed'
  end
  
  def update_from_openai!(job_response)
    update!(
      status: job_response.status,
      fine_tuned_model: job_response.fine_tuned_model,
      finished_at: job_response.finished_at ? Time.at(job_response.finished_at) : nil,
      trained_tokens: job_response.trained_tokens,
      error_message: job_response.error&.message
    )
    
    if job_response.result_files.present?
      update!(training_metrics: extract_metrics_from_results(job_response.result_files))
    end
    
    calculate_training_cost! if completed?
  end
  
  def check_status!
    return unless pending?
    
    response = OPENAI.fine_tuning.jobs.retrieve(id: openai_job_id)
    update_from_openai!(response)
  rescue => e
    Rails.logger.error "Failed to check fine-tune status: #{e.message}"
    update!(error_message: e.message)
  end
  
  def cancel!
    return unless pending?
    
    OPENAI.fine_tuning.jobs.cancel(id: openai_job_id)
    update!(status: 'cancelled', finished_at: Time.current)
  rescue => e
    Rails.logger.error "Failed to cancel fine-tune: #{e.message}"
    update!(error_message: e.message)
  end
  
  def deploy!
    return unless completed? && fine_tuned_model.present?
    
    # Update the settings to use this model
    OpenaiSetting.set(
      'model_routing',
      fine_tuned_model,
      category: 'model',
      model_type: 'routing',
      description: "Fine-tuned router model from job #{openai_job_id}"
    )
    
    # Also store in environment config
    Rails.application.config.openai[:fine_tune_model] = fine_tuned_model
    
    true
  end
  
  def duration
    return nil unless started_at
    
    end_time = finished_at || Time.current
    end_time - started_at
  end
  
  def duration_in_words
    return nil unless duration
    
    seconds = duration.to_i
    if seconds < 60
      "#{seconds} seconds"
    elsif seconds < 3600
      "#{seconds / 60} minutes"
    else
      "#{seconds / 3600} hours"
    end
  end
  
  private
  
  def calculate_training_cost!
    return unless trained_tokens
    
    # Pricing as of 2024 (update as needed)
    # GPT-4o-mini fine-tuning: $0.002 per 1K tokens
    # GPT-3.5-turbo fine-tuning: $0.008 per 1K tokens
    
    rate_per_1k = case base_model
                  when /gpt-4o-mini/
                    0.002
                  when /gpt-3\.5-turbo/
                    0.008
                  else
                    0.01  # Default conservative estimate
                  end
    
    cost = (trained_tokens / 1000.0) * rate_per_1k
    update_column(:training_cost, cost.round(4))
  end
  
  def extract_metrics_from_results(result_files)
    # This would download and parse the result files to extract metrics
    # For now, return empty hash
    {}
  end
end