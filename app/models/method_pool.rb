# frozen_string_literal: true

# == Schema Information
#
# Table name: method_pools
#
#  id                       :bigint           not null, primary key
#  method_name              :string           not null
#  category                 :string
#  description              :text             not null
#  steps                    :jsonb
#  prerequisites            :jsonb
#  outcomes                 :jsonb
#  repr_text                :text             not null
#  provenance_and_rights_id :bigint           not null
#  valid_time_start         :datetime         not null
#  valid_time_end           :datetime
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#
# Indexes
#
#  index_method_pools_on_category                             (category)
#  index_method_pools_on_method_name                          (method_name)
#  index_method_pools_on_provenance_and_rights_id             (provenance_and_rights_id)
#  index_method_pools_on_valid_time_start_and_valid_time_end  (valid_time_start,valid_time_end)
#
class MethodPool < ApplicationRecord
  include EknPoolEntity
  
  # Category enum for method classification
  enum :category, {
    analytical: 0,      # Statistical analysis, data analysis methods
    experimental: 1,    # Laboratory experiments, field experiments
    observational: 2,   # Field observations, monitoring protocols  
    computational: 3,   # Modeling, simulation methods
    theoretical: 4      # Conceptual frameworks, theoretical approaches
  }
  
  # Complexity enum based on steps and prerequisites
  enum :complexity_level, {
    simple: 0,          # 0-2 total elements
    moderate: 1,        # 3-5 total elements
    complex: 2,         # 6-10 total elements  
    very_complex: 3     # 10+ total elements
  }
  
  # Relationships (EknPoolEntity provides provenance_and_rights)
  has_many :method_pool_practicals, dependent: :destroy
  has_many :practicals, through: :method_pool_practicals
  
  # Additional validations (EknPoolEntity provides common ones)
  validates :method_name, presence: true, length: { maximum: 255 }
  validates :description, presence: true, length: { maximum: 2000 }
  
  # Model-driven extraction configuration
  extraction_config do
    canonical_name "MethodAndModel"
    description "Research methods, methodologies, evaluation patterns - systematic approaches to investigation"
    
    field :method_name, type: :string, required: true,
      examples: [
        "Statistical analysis methodology",
        "Arctic field sampling protocol",
        "Climate data modeling approach",
        "Environmental impact assessment",
        "Remote sensing technique"
      ],
      hints: "Look for specific research methods, analytical techniques, systematic approaches, protocols, or methodologies"
      
    field :category, type: :enum,
      values: -> { categories.keys },  # Live from model enum!
      default: 'analytical',
      hints: "analytical: statistics/data analysis; experimental: lab/field experiments; observational: monitoring/field studies; computational: modeling/simulation; theoretical: frameworks/concepts"
      
    field :complexity_level, type: :enum,
      values: -> { complexity_levels.keys },  # Live from model enum!
      default: 'simple',
      hints: "simple: basic methods; moderate: multi-step processes; complex: elaborate protocols; very_complex: highly sophisticated approaches"
      
    field :description, type: :text, required: true,
      examples: [
        "Comprehensive statistical analysis approach for Arctic climate data",
        "Standardized protocol for collecting ice core samples",
        "Machine learning model for predicting sea ice coverage"
      ],
      hints: "Detailed description of what the method does, its purpose, and application context"
      
    field :steps, type: :json, required: false,
      examples: [
        ["Collect samples", "Analyze composition", "Generate report"],
        ["Data preparation", "Model training", "Validation", "Results interpretation"]
      ],
      hints: "Array of step descriptions for executing this method"
      
    field :prerequisites, type: :json, required: false,
      examples: [
        ["Basic statistical knowledge", "Access to R software"],
        ["Laboratory equipment", "Safety training", "Sample collection permits"]
      ],
      hints: "Array of requirements needed before applying this method"
  end
  
  # Scopes
  scope :by_category, ->(category) { where(category: category) }
  scope :active_during, ->(time) { where('valid_time_start <= ? AND (valid_time_end IS NULL OR valid_time_end >= ?)', time, time) }
  scope :with_prerequisites, -> { where("jsonb_array_length(prerequisites) > 0") }
  scope :without_prerequisites, -> { where("prerequisites = '[]'::jsonb") }
  
  # Callbacks
  before_validation :generate_repr_text, if: -> { repr_text.blank? }
  
  def step_count
    steps.is_a?(Array) ? steps.size : 0
  end
  
  def prerequisite_count
    prerequisites.is_a?(Array) ? prerequisites.size : 0
  end
  
  def outcome_count
    outcomes.is_a?(Array) ? outcomes.size : 0
  end
  
  def has_prerequisites?
    prerequisite_count > 0
  end
  
  def complexity
    # Simple heuristic based on steps and prerequisites
    total = step_count + prerequisite_count
    
    case total
    when 0..2 then 'simple'
    when 3..5 then 'moderate'
    when 6..10 then 'complex'
    else 'very_complex'
    end
  end
  
  private
  
  def generate_repr_text
    category_text = category.present? ? " [#{category}]" : ""
    steps_text = step_count > 0 ? " (#{step_count} steps)" : ""
    prereq_text = prerequisite_count > 0 ? " - Requires #{prerequisite_count} prerequisites" : ""
    
    self.repr_text = "Method: #{method_name}#{category_text}#{steps_text} - #{description}#{prereq_text}"
  end
end
