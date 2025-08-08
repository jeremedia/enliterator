# frozen_string_literal: true

# == Schema Information
#
# Table name: pipeline_runs
#
#  id            :bigint           not null, primary key
#  bundle_path   :string           not null
#  stage         :string           not null
#  status        :string           not null
#  started_at    :datetime         not null
#  completed_at  :datetime
#  metrics       :jsonb
#  options       :jsonb
#  file_count    :integer
#  error_message :text
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
# Indexes
#
#  index_pipeline_runs_on_stage             (stage)
#  index_pipeline_runs_on_stage_and_status  (stage,status)
#  index_pipeline_runs_on_started_at        (started_at)
#  index_pipeline_runs_on_status            (status)
#
# Track pipeline execution runs
class PipelineRun < ApplicationRecord
  # Enums
  enum :status, {
    pending: "pending",
    running: "running",
    completed: "completed",
    failed: "failed",
    aborted: "aborted"
  }, prefix: true
  
  enum :stage, {
    intake: "intake",
    rights_triage: "rights_triage",
    lexicon_bootstrap: "lexicon_bootstrap",
    pool_filling: "pool_filling",
    graph_assembly: "graph_assembly",
    representation: "representation",
    literacy_scoring: "literacy_scoring",
    deliverables: "deliverables"
  }, prefix: true
  
  # Associations
  has_many :pipeline_artifacts, dependent: :destroy
  has_many :pipeline_errors, dependent: :destroy
  
  # Validations
  validates :bundle_path, presence: true
  validates :stage, presence: true
  validates :status, presence: true
  validates :started_at, presence: true
  
  # Scopes
  scope :recent, -> { order(started_at: :desc) }
  scope :successful, -> { status_completed }
  scope :failed, -> { status_failed }
  scope :by_stage, ->(stage) { where(stage: stage) }
  
  # Callbacks
  before_validation :set_defaults
  
  # Instance methods
  def duration
    return nil unless started_at
    (completed_at || Time.current) - started_at
  end
  
  def success_rate
    return 0.0 unless metrics&.dig("total_items").to_i > 0
    
    successful = metrics.dig("successful_items").to_f
    total = metrics.dig("total_items").to_f
    
    (successful / total * 100).round(2)
  end
  
  def record_failure(stage:, error:)
    pipeline_errors.create!(
      stage: stage,
      error_type: error.class.name,
      message: error,
      occurred_at: Time.current
    )
    
    increment_metric("errors.#{stage}")
  end
  
  def record_artifact(type:, path:, metadata: {})
    pipeline_artifacts.create!(
      artifact_type: type,
      file_path: path,
      metadata: metadata,
      created_at: Time.current
    )
  end
  
  def increment_metric(key, value = 1)
    self.metrics ||= {}
    self.metrics[key] = (metrics[key] || 0) + value
    save!
  end
  
  def set_metric(key, value)
    self.metrics ||= {}
    self.metrics[key] = value
    save!
  end
  
  private
  
  def set_defaults
    self.status ||= :pending
    self.started_at ||= Time.current
    self.metrics ||= {}
    self.options ||= {}
  end
end
