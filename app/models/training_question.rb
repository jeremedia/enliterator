# frozen_string_literal: true

# TrainingQuestion - Individual training questions for EKN evaluation
#
# Each question tests specific aspects of an EKN's knowledge and personality archetype.
# Questions are generated from the EKN's actual knowledge graph content.
#
class TrainingQuestion < ApplicationRecord
  include Loggable
  
  belongs_to :training_question_set
  belongs_to :ekn
  has_many :training_responses, dependent: :destroy
  
  validates :question_text, presence: true, length: { minimum: 10, maximum: 1000 }
  validates :question_type, presence: true
  validates :difficulty_level, inclusion: { in: %w[easy medium hard expert] }
  
  enum :question_type, {
    meta_navigation: 'meta_navigation',
    framework_understanding: 'framework_understanding', 
    domain_specific: 'domain_specific',
    relationship_mapping: 'relationship_mapping',
    architectural_knowledge: 'architectural_knowledge',
    process_understanding: 'process_understanding',
    troubleshooting: 'troubleshooting'
  }
  
  enum :difficulty_level, {
    easy: 'easy',
    medium: 'medium',
    hard: 'hard',
    expert: 'expert'
  }
  
  enum :archetype_focus, {
    master_navigator: 'master_navigator',
    precision_analyst: 'precision_analyst',
    systematic_explorer: 'systematic_explorer', 
    relationship_mapper: 'relationship_mapper',
    domain_specialist: 'domain_specialist',
    creative_synthesizer: 'creative_synthesizer',
    data_detective: 'data_detective',
    any_archetype: 'any_archetype'
  }, validate: false
  
  scope :active, -> { where(active: true) }
  scope :for_archetype, ->(archetype) { where(archetype_focus: archetype) }
  scope :by_difficulty, ->(level) { where(difficulty_level: level) }
  scope :by_type, ->(type) { where(question_type: type) }
  scope :frequently_used, -> { where('times_asked > ?', 5) }
  scope :high_performing, -> { where('avg_score > ?', 0.8) }
  scope :needs_improvement, -> { where('avg_score < ? AND times_asked > ?', 0.6, 3) }
  
  # Get archetype that should excel at this question
  def target_archetype
    archetype_focus&.to_sym || determine_target_archetype
  end
  
  # Determine which archetype should be best at this question
  def determine_target_archetype
    case question_type.to_sym
    when :meta_navigation
      :master_navigator
    when :framework_understanding
      :master_navigator
    when :domain_specific
      :domain_specialist  
    when :relationship_mapping
      :relationship_mapper
    when :architectural_knowledge
      :systematic_explorer
    when :process_understanding
      :systematic_explorer
    when :troubleshooting
      :data_detective
    else
      :any_archetype
    end
  end
  
  # Record that this question was asked
  def record_usage!(response_score = nil)
    increment!(:times_asked)
    
    if response_score
      # Update running average
      current_total = avg_score * (times_asked - 1)
      new_avg = (current_total + response_score) / times_asked
      update!(avg_score: new_avg)
    end
  end
  
  # Check if question is performing well
  def performing_well?
    return false if times_asked < 3
    avg_score > 0.7
  end
  
  # Check if question needs review
  def needs_review?
    return false if times_asked < 3
    avg_score < 0.5
  end
  
  # Get performance category
  def performance_category
    return :untested if times_asked < 3
    return :excellent if avg_score > 0.9
    return :good if avg_score > 0.7
    return :fair if avg_score > 0.5
    :poor
  end
  
  # Get question difficulty description
  def difficulty_description
    case difficulty_level.to_sym
    when :easy
      "Basic knowledge - foundational concepts"
    when :medium  
      "Intermediate understanding - connecting concepts"
    when :hard
      "Advanced knowledge - complex relationships"
    when :expert
      "Expert level - deep architectural understanding"
    end
  end
  
  # Get expected knowledge areas as array
  def knowledge_areas
    expected_knowledge_areas || []
  end
  
  # Check if question targets specific archetype
  def archetype_specific?
    archetype_focus.present? && archetype_focus != 'any_archetype'
  end
  
  # Get evaluation criteria as hash
  def criteria
    evaluation_criteria || {}
  end
  
  # Get generation source details
  def source_details
    generation_source || {}
  end
  
  # Summary for display
  def summary
    {
      id: id,
      question: question_text.truncate(100),
      type: question_type.humanize,
      archetype: archetype_focus&.humanize || 'Any',
      difficulty: difficulty_level.humanize,
      performance: "#{avg_score.round(2)} (#{times_asked}x)",
      status: performance_category.to_s.humanize
    }
  end
end