# frozen_string_literal: true

# Intent and Task pool: user intents, queries, and deliverable requests
class IntentAndTask < ApplicationRecord
  include HasRights
  include TimeTrackable

  # Enums
  enum :deliverable_type, {
    answer: "answer",
    webpage: "webpage",
    markdown: "markdown",
    pdf: "pdf",
    table: "table",
    map: "map",
    timeline: "timeline",
    outline: "outline",
    voice_script: "voice_script",
    data_export: "data_export",
    visualization: "visualization"
  }, prefix: true

  enum :modality, {
    text: "text",
    voice: "voice",
    gesture: "gesture",
    multimodal: "multimodal"
  }, prefix: true

  enum :status, {
    pending: "pending",
    processing: "processing",
    completed: "completed",
    failed: "failed",
    cancelled: "cancelled"
  }, prefix: true

  # Associations
  belongs_to :user_session, optional: true, class_name: "Runtime::Session"

  # Validations
  validates :raw_intent, presence: true
  validates :deliverable_type, presence: true
  validates :modality, presence: true
  validates :status, presence: true
  validates :repr_text, presence: true, length: { maximum: 500 }
  validates :observed_at, presence: true

  # Scopes
  scope :recent, -> { order(observed_at: :desc) }
  scope :by_deliverable, ->(type) { where(deliverable_type: type) }
  scope :successful, -> { status_completed }
  scope :with_constraints, -> { where.not(constraints: {}) }
  scope :with_persona, -> { where("constraints->>'persona' IS NOT NULL") }

  # Callbacks
  before_validation :set_defaults
  before_validation :generate_repr_text
  after_commit :sync_to_graph, on: [:create, :update]
  after_commit :remove_from_graph, on: :destroy
  after_create :enqueue_processing

  # Instance methods
  def normalized_query
    normalized_intent&.dig("query") || raw_intent
  end

  def extracted_entities
    normalized_intent&.dig("entities") || []
  end

  def detected_pools
    normalized_intent&.dig("pools") || []
  end

  def time_constraints
    constraints&.dig("time") || {}
  end

  def spatial_constraints
    constraints&.dig("spatial") || {}
  end

  def persona_style
    constraints&.dig("persona", "style") || "neutral"
  end

  def execution_time
    return nil unless status_completed? && resolved_at
    resolved_at - observed_at
  end

  def retry_count
    metadata&.dig("retry_count") || 0
  end

  def mark_completed!(result)
    update!(
      status: :completed,
      resolved_at: Time.current,
      metadata: metadata.merge(result: result)
    )
  end

  def mark_failed!(error)
    update!(
      status: :failed,
      resolved_at: Time.current,
      metadata: metadata.merge(
        error: error.message,
        retry_count: retry_count + 1
      )
    )
  end

  def can_retry?
    status_failed? && retry_count < 3
  end

  def related_intents
    return [] unless normalized_intent&.dig("entities").present?
    
    entity_ids = normalized_intent["entities"].pluck("id")
    self.class
      .where.not(id: id)
      .where("normalized_intent->'entities' @> ?", entity_ids.to_json)
      .limit(5)
  end

  private

  def set_defaults
    self.observed_at ||= Time.current
    self.status ||= :pending
    self.constraints ||= {}
    self.metadata ||= {}
    self.normalized_intent ||= {}
  end

  def generate_repr_text
    type_label = deliverable_type&.humanize || "Unknown"
    query_preview = raw_intent.truncate(150)
    
    self.repr_text = "#{type_label} request: #{query_preview}"
  end

  def sync_to_graph
    return unless defined?(Graph::IntentWriter)
    Graph::IntentWriter.new(self).sync
  rescue StandardError => e
    Rails.logger.error "Failed to sync IntentAndTask #{id} to graph: #{e.message}"
  end

  def remove_from_graph
    Graph::IntentRemover.new(self).remove
  rescue StandardError => e
    Rails.logger.error "Failed to remove IntentAndTask #{id} from graph: #{e.message}"
  end

  def enqueue_processing
    return unless status_pending?
    
    # Skip job queueing if jobs are not yet defined
    return unless defined?(Runtime::AnswerJob)
    
    # Enqueue the appropriate job based on deliverable type
    case deliverable_type
    when "answer"
      Runtime::AnswerJob.perform_later(self)
    when "webpage", "markdown", "pdf"
      Runtime::DocumentJob.perform_later(self)
    when "map"
      Runtime::MapJob.perform_later(self)
    when "timeline"
      Runtime::TimelineJob.perform_later(self)
    else
      Runtime::GenericDeliverableJob.perform_later(self)
    end
  rescue StandardError => e
    Rails.logger.error "Failed to enqueue processing for IntentAndTask #{id}: #{e.message}"
    # Don't call mark_failed! during creation as it causes a save loop
  end
end