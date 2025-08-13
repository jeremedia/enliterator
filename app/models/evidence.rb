# frozen_string_literal: true

# == Schema Information
#
# Table name: evidences
#
#  id                       :bigint           not null, primary key
#  evidence_type            :string           not null
#  description              :text             not null
#  source_refs              :jsonb
#  confidence_score         :float
#  corroboration            :jsonb
#  repr_text                :text             not null
#  provenance_and_rights_id :bigint           not null
#  observed_at              :datetime         not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#
# Indexes
#
#  index_evidences_on_confidence_score          (confidence_score)
#  index_evidences_on_evidence_type             (evidence_type)
#  index_evidences_on_observed_at               (observed_at)
#  index_evidences_on_provenance_and_rights_id  (provenance_and_rights_id)
#
class Evidence < ApplicationRecord
  include EknPoolEntity
  
  # Evidence type enum for data classification
  enum :evidence_type, {
    measurement: 0,       # Quantitative measurements, sensor data
    observation: 1,       # Qualitative field observations
    document: 2,          # Written records, reports, publications
    testimony: 3,         # Witness accounts, interviews, statements
    sensor_data: 4,       # Automated sensor readings
    laboratory_result: 5, # Lab analysis results
    survey_response: 6,   # Survey and questionnaire data
    multimedia: 7         # Photos, videos, audio recordings
  }
  
  # Note: confidence_level is calculated dynamically from confidence_score
  # See calculated_confidence_level method below
  
  # Relationships (EknPoolEntity provides provenance_and_rights)
  has_many :evidence_experiences, dependent: :destroy
  has_many :experiences, through: :evidence_experiences
  
  # Additional validations (EknPoolEntity provides common ones)
  validates :description, presence: true, length: { maximum: 2000 }
  validates :observed_at, presence: true
  validates :confidence_score, numericality: { in: 0..1 }, allow_nil: true
  
  # Model-driven extraction configuration
  extraction_config do
    canonical_name "EvidenceAndObservation"
    description "Primary data, measurements, logs, transcripts - empirical evidence and observations"
    
    field :evidence_type, type: :enum,
      values: -> { evidence_types.keys },  # Live from model enum!
      default: 'measurement',
      hints: "measurement: quantitative data; observation: qualitative notes; document: written records; testimony: interviews; sensor_data: automated readings; laboratory_result: lab analysis; survey_response: questionnaire data; multimedia: photos/videos"
      
    field :description, type: :text, required: true,
      examples: [
        "Temperature measurements from Arctic weather station",
        "Ice thickness observations during field expedition",
        "Climate research report from NOAA",
        "Researcher interview about permafrost changes",
        "Automated sea ice extent readings"
      ],
      hints: "Detailed description of what evidence was collected, measured, or observed"
      
    # Note: confidence_level is calculated from confidence_score, not extracted directly
      
    field :confidence_score, type: :float, required: false,
      examples: [0.95, 0.87, 0.73, 0.42],
      hints: "Numerical confidence score between 0.0 and 1.0, where 1.0 is highest confidence"
      
    field :observed_at, type: :datetime, required: true,
      examples: ["2023-08-15", "2022-12-03", "2024-01-20"],
      hints: "When this evidence was collected, observed, or recorded"
      
    field :source_refs, type: :json, required: false,
      examples: [
        ["Station ID: ARCTIC-01", "Instrument: Thermometer"],
        ["Publication: Arctic Climate Report 2023", "Author: Dr. Johnson"]
      ],
      hints: "Array of source references, citations, or data provenance information"
  end
  
  # Scopes
  scope :by_type, ->(type) { where(evidence_type: type) }
  scope :high_confidence, -> { where('confidence_score >= ?', 0.8) }
  scope :medium_confidence, -> { where('confidence_score >= ? AND confidence_score < ?', 0.5, 0.8) }
  scope :low_confidence, -> { where('confidence_score < ?', 0.5) }
  scope :observed_between, ->(start_date, end_date) { where(observed_at: start_date..end_date) }
  
  # Callbacks
  before_validation :generate_repr_text, if: -> { repr_text.blank? }
  
  def calculated_confidence_level
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
