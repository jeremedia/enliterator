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
  include EknPoolEntity
  
  # Risk type enum for risk classification
  enum :risk_type, {
    safety: 0,          # Personnel safety, accidents, injuries
    environmental: 1,   # Environmental damage, pollution, ecosystem impact
    operational: 2,     # Operational failures, equipment breakdown
    regulatory: 3,      # Compliance violations, legal issues
    technical: 4,       # Technical failures, system malfunctions
    financial: 5,       # Budget overruns, funding issues
    reputational: 6,    # Public relations, institutional reputation
    data: 7            # Data loss, privacy breaches, information security
  }
  
  # Severity enum (existing - perfect for extraction!)
  enum :severity, {
    negligible: 'negligible',
    minor: 'minor',
    moderate: 'moderate',
    major: 'major',
    critical: 'critical'
  }, prefix: true
  
  # Relationships (EknPoolEntity provides provenance_and_rights)
  has_many :risk_practicals, dependent: :destroy
  has_many :practicals, through: :risk_practicals
  
  # Additional validations (EknPoolEntity provides common ones)
  validates :description, presence: true, length: { maximum: 2000 }
  validates :probability, numericality: { in: 0..1 }, allow_nil: true
  
  # Model-driven extraction configuration
  extraction_config do
    canonical_name "RiskAndGovernance"
    description "Hazards, mitigations, approvals, compliance - risk management and governance entities"
    
    field :risk_type, type: :enum,
      values: -> { risk_types.keys },  # Live from model enum!
      default: 'safety',
      hints: "safety: personnel risks; environmental: ecosystem damage; operational: equipment failures; regulatory: compliance issues; technical: system malfunctions; financial: budget risks; reputational: PR concerns; data: information security"
      
    field :severity, type: :enum,
      values: -> { severities.keys },  # Live from model enum!
      default: 'moderate',
      hints: "negligible: minimal impact; minor: small problems; moderate: significant issues; major: serious consequences; critical: catastrophic outcomes"
      
    field :description, type: :text, required: true,
      examples: [
        "Risk of equipment failure in extreme Arctic conditions",
        "Environmental impact from research activities on wildlife",
        "Safety protocols for researchers working on sea ice",
        "Regulatory compliance for cross-border Arctic research",
        "Data security risks for sensitive research information"
      ],
      hints: "Detailed description of the risk, its potential causes, and possible consequences"
      
    field :probability, type: :float, required: false,
      examples: [0.15, 0.35, 0.67, 0.89],
      hints: "Likelihood of risk occurrence as decimal between 0.0 (never) and 1.0 (certain)"
      
    field :mitigations, type: :json, required: false,
      examples: [
        ["Regular equipment maintenance", "Backup systems", "Emergency procedures"],
        ["Environmental impact assessments", "Wildlife monitoring", "Seasonal restrictions"]
      ],
      hints: "Array of mitigation strategies, preventive measures, or risk reduction actions"
      
    field :impacts, type: :json, required: false,
      examples: [
        ["Research delays", "Equipment damage", "Safety incidents"],
        ["Ecosystem disruption", "Species displacement", "Regulatory violations"]
      ],
      hints: "Array of potential impacts or consequences if this risk materializes"
  end
  
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
