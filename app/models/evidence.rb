# frozen_string_literal: true

# Evidence Pool - Represents supporting evidence or proof
# Used to track claims, assertions, and their supporting documentation
class Evidence < ApplicationRecord
  belongs_to :provenance_and_rights
  
  # Relationships
  has_many :evidence_experiences, dependent: :destroy
  has_many :experiences, through: :evidence_experiences
  
  # Validations
  validates :evidence_type, presence: true
  validates :description, presence: true
  validates :repr_text, presence: true
  validates :observed_at, presence: true
  validates :confidence_score, numericality: { in: 0..1 }, allow_nil: true
  
  # Scopes
  scope :by_type, ->(type) { where(evidence_type: type) }
  scope :high_confidence, -> { where('confidence_score >= ?', 0.8) }
  scope :medium_confidence, -> { where('confidence_score >= ? AND confidence_score < ?', 0.5, 0.8) }
  scope :low_confidence, -> { where('confidence_score < ?', 0.5) }
  scope :observed_between, ->(start_date, end_date) { where(observed_at: start_date..end_date) }
  
  # Callbacks
  before_validation :generate_repr_text, if: -> { repr_text.blank? }
  
  def confidence_level
    return 'unknown' if confidence_score.nil?
    
    case confidence_score
    when 0.8..1.0 then 'high'
    when 0.5...0.8 then 'medium'
    when 0...0.5 then 'low'
    else 'unknown'
    end
  end
  
  def has_corroboration?
    corroboration.present? && corroboration.any?
  end
  
  def source_count
    source_refs.is_a?(Array) ? source_refs.size : 0
  end
  
  private
  
  def generate_repr_text
    confidence_text = confidence_score ? " (#{(confidence_score * 100).round}% confidence)" : ""
    sources_text = source_count > 0 ? " [#{source_count} sources]" : ""
    
    self.repr_text = "Evidence: #{evidence_type}#{confidence_text} - #{description}#{sources_text}" +
                     " (Observed: #{observed_at.to_date})"
  end
end