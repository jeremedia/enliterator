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
# MethodPool - Represents methods, procedures, or techniques
# Named 'MethodPool' to avoid conflict with Ruby's built-in Method class
# Used to track procedural knowledge and techniques
class MethodPool < ApplicationRecord
  belongs_to :provenance_and_rights
  
  # Relationships
  has_many :method_pool_practicals, dependent: :destroy
  has_many :practicals, through: :method_pool_practicals
  
  # Validations
  validates :method_name, presence: true
  validates :description, presence: true
  validates :repr_text, presence: true
  validates :valid_time_start, presence: true
  
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
