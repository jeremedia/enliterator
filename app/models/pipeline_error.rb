# frozen_string_literal: true

# == Schema Information
#
# Table name: pipeline_errors
#
#  id              :bigint           not null, primary key
#  pipeline_run_id :bigint           not null
#  stage           :string           not null
#  error_type      :string           not null
#  message         :text
#  occurred_at     :datetime         not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#
# Indexes
#
#  index_pipeline_errors_on_pipeline_run_id  (pipeline_run_id)
#  index_pipeline_errors_on_stage            (stage)
#
class PipelineError < ApplicationRecord
  belongs_to :pipeline_run
  
  # Validations
  validates :stage, presence: true
  validates :error_type, presence: true
  validates :occurred_at, presence: true
  
  # Scopes
  scope :by_stage, ->(stage) { where(stage: stage) }
  scope :by_type, ->(type) { where(error_type: type) }
  scope :recent, -> { order(occurred_at: :desc) }
  scope :critical, -> { where("error_type LIKE ?", "%Critical%") }
  
  # Instance methods
  def critical?
    error_type.include?("Critical") || error_type.include?("Fatal")
  end
  
  def retryable?
    !critical? && !error_type.include?("Validation")
  end
  
  def error_summary
    "#{stage}: #{error_type} - #{message&.truncate(100)}"
  end
end
