# frozen_string_literal: true

# Represents a batch of items being processed through the pipeline
class IngestBatch < ApplicationRecord
  has_many :ingest_items, dependent: :destroy
  
  # Status tracking for pipeline stages
  enum :status, {
    pending: 0,
    intake_in_progress: 1,
    intake_completed: 2,
    intake_failed: 3,
    triage_in_progress: 4,
    triage_completed: 5,
    triage_needs_review: 6,
    triage_failed: 7,
    lexicon_in_progress: 8,
    lexicon_completed: 9,
    pool_filling_in_progress: 10,
    pool_filling_completed: 11,
    graph_assembly_in_progress: 12,
    graph_assembly_completed: 13,
    representations_in_progress: 14,
    representations_completed: 15,
    scoring_in_progress: 16,
    scoring_completed: 17,
    deliverables_in_progress: 18,
    completed: 19,
    failed: 20
  }, prefix: true
  
  # Validations
  validates :name, presence: true
  validates :source_type, presence: true
  
  # Scopes
  scope :recent, -> { order(created_at: :desc) }
  scope :completed, -> { where(status: :completed) }
  scope :failed, -> { where(status: [:intake_failed, :triage_failed, :failed]) }
  scope :needs_review, -> { where(status: :triage_needs_review) }
  
  # Callbacks
  before_validation :set_defaults
  
  def progress_percentage
    return 0 if status_pending?
    return 100 if status_completed?
    
    # Map status to rough percentage
    status_mapping = {
      intake_in_progress: 5,
      intake_completed: 10,
      triage_in_progress: 15,
      triage_completed: 20,
      lexicon_in_progress: 30,
      lexicon_completed: 35,
      pool_filling_in_progress: 45,
      pool_filling_completed: 50,
      graph_assembly_in_progress: 60,
      graph_assembly_completed: 65,
      representations_in_progress: 75,
      representations_completed: 80,
      scoring_in_progress: 85,
      scoring_completed: 90,
      deliverables_in_progress: 95
    }
    
    status_mapping[status.to_sym] || 0
  end
  
  def items_by_status
    ingest_items.group(:triage_status).count
  end
  
  def restart_pipeline!
    update!(status: :pending)
    ingest_items.update_all(triage_status: 'pending')
    Pipeline::IntakeJob.perform_later(id)
  end
  
  private
  
  def set_defaults
    self.metadata ||= {}
    self.statistics ||= {}
  end
end