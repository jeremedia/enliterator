# frozen_string_literal: true

# Represents an individual item in an ingest batch
class IngestItem < ApplicationRecord
  belongs_to :ingest_batch
  belongs_to :provenance_and_rights, optional: true
  
  # Polymorphic association for the created pool item
  belongs_to :pool_item, polymorphic: true, optional: true
  
  # Triage status tracking
  enum :triage_status, {
    pending: 'pending',
    in_progress: 'in_progress',
    completed: 'completed',
    quarantined: 'quarantined',
    failed: 'failed',
    skipped: 'skipped'
  }, prefix: true
  
  # Media type categories
  # These types determine how content is processed through the pipeline
  enum :media_type, {
    text: 'text',           # Plain text, markdown, documentation
    code: 'code',           # Source code files (Ruby, Python, JS, etc.)
    config: 'config',       # Configuration files (YAML, JSON configs, XML configs)
    data: 'data',           # Data files (CSV, JSON data, XML data)
    document: 'document',   # Rich documents (PDF, Word, etc.)
    image: 'image',         # Image files (PNG, JPG, GIF, etc.)
    audio: 'audio',         # Audio files (MP3, WAV, etc.)
    video: 'video',         # Video files (MP4, AVI, etc.)
    structured: 'structured', # Generic structured data (backwards compatibility)
    binary: 'binary',       # Other binary files
    unknown: 'unknown'      # Unable to determine type
  }, prefix: true
  
  # Validations
  validates :source_hash, presence: true, uniqueness: true
  validates :file_path, presence: true
  validates :media_type, presence: true
  validates :size_bytes, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  
  # Scopes
  scope :pending_triage, -> { where(triage_status: 'pending') }
  scope :triaged, -> { where(triage_status: ['completed', 'quarantined']) }
  scope :with_rights, -> { where.not(provenance_and_rights_id: nil) }
  scope :quarantined, -> { where(triage_status: 'quarantined') }
  
  # Callbacks
  before_validation :set_defaults
  before_validation :compute_source_hash
  
  def readable?
    media_type_text? || media_type_structured?
  end
  
  def processable?
    !triage_status_failed? && !triage_status_skipped?
  end
  
  def has_rights?
    provenance_and_rights_id.present?
  end
  
  def quarantine!(reason)
    update!(
      triage_status: 'quarantined',
      triage_metadata: (triage_metadata || {}).merge(
        quarantine_reason: reason,
        quarantined_at: Time.current
      )
    )
  end
  
  def attach_to_pool_item(item)
    update!(
      pool_item: item,
      metadata: (metadata || {}).merge(
        pool_type: item.class.name,
        pool_id: item.id,
        attached_at: Time.current
      )
    )
  end
  
  private
  
  def set_defaults
    self.triage_status ||= 'pending'
    self.media_type ||= 'unknown'
    self.metadata ||= {}
    self.triage_metadata ||= {}
  end
  
  def compute_source_hash
    return if source_hash.present?
    return unless file_path.present?
    
    # Compute a stable hash from file path and batch info
    content = "#{ingest_batch&.id}:#{file_path}:#{source_type}"
    self.source_hash = Digest::SHA256.hexdigest(content)
  end
end