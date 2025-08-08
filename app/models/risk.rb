# frozen_string_literal: true

# == Schema Information
#
# Table name: risks
#
#  id                       :bigint           not null, primary key
#  risk_type                :string           not null
#  severity                 :string
#  probability              :float
#  description              :text             not null
#  mitigations              :jsonb
#  impacts                  :jsonb
#  repr_text                :text             not null
#  provenance_and_rights_id :bigint           not null
#  valid_time_start         :datetime         not null
#  valid_time_end           :datetime
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#
# Indexes
#
#  index_risks_on_probability                          (probability)
#  index_risks_on_provenance_and_rights_id             (provenance_and_rights_id)
#  index_risks_on_risk_type                            (risk_type)
#  index_risks_on_severity                             (severity)
#  index_risks_on_valid_time_start_and_valid_time_end  (valid_time_start,valid_time_end)
#
class Risk < ApplicationRecord
  belongs_to :provenance_and_rights
  
  # Relationships
  has_many :risk_practicals, dependent: :destroy
  has_many :practicals, through: :risk_practicals
  
  # Validations
  validates :risk_type, presence: true
  validates :description, presence: true
  validates :repr_text, presence: true
  validates :valid_time_start, presence: true
  validates :probability, numericality: { in: 0..1 }, allow_nil: true
  
  # Enums
  enum :severity, {
    negligible: 'negligible',
    minor: 'minor',
    moderate: 'moderate',
    major: 'major',
    critical: 'critical'
  }, prefix: true
  
  # Scopes
  scope :by_type, ->(type) { where(risk_type: type) }
  scope :by_severity, ->(severity) { where(severity: severity) }
  scope :high_probability, -> { where('probability >= ?', 0.7) }
  scope :medium_probability, -> { where('probability >= ? AND probability < ?', 0.3, 0.7) }
  scope :low_probability, -> { where('probability < ?', 0.3) }
  scope :active_during, ->(time) { where('valid_time_start <= ? AND (valid_time_end IS NULL OR valid_time_end >= ?)', time, time) }
  
  # Callbacks
  before_validation :generate_repr_text, if: -> { repr_text.blank? }
  
  def risk_level
    return 'unknown' unless severity.present? && probability.present?
    
    # Simple risk matrix calculation
    severity_score = case severity
                    when 'critical' then 5
                    when 'major' then 4
                    when 'moderate' then 3
                    when 'minor' then 2
                    when 'negligible' then 1
                    else 1
                    end
    
    risk_score = severity_score * probability
    
    case risk_score
    when 3.5..5.0 then 'very_high'
    when 2.5...3.5 then 'high'
    when 1.5...2.5 then 'medium'
    when 0.5...1.5 then 'low'
    else 'very_low'
    end
  end
  
  def has_mitigations?
    mitigations.present? && mitigations.any?
  end
  
  def mitigation_count
    mitigations.is_a?(Array) ? mitigations.size : 0
  end
  
  def impact_count
    impacts.is_a?(Array) ? impacts.size : 0
  end
  
  private
  
  def generate_repr_text
    probability_text = probability ? " (#{(probability * 100).round}% probability)" : ""
    severity_text = severity.present? ? " [#{severity.upcase}]" : ""
    mitigation_text = mitigation_count > 0 ? " - #{mitigation_count} mitigations" : ""
    
    self.repr_text = "Risk: #{risk_type}#{severity_text}#{probability_text} - #{description}#{mitigation_text}"
  end
end
