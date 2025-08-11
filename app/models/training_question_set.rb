# frozen_string_literal: true

# TrainingQuestionSet - Groups of training questions for systematic EKN evaluation
#
# Each EKN gets training question sets generated from their actual knowledge graph.
# Questions test archetype-specific capabilities and domain understanding.
#
class TrainingQuestionSet < ApplicationRecord
  include Loggable
  
  belongs_to :ekn
  has_many :training_questions, dependent: :destroy
  has_many :training_runs, dependent: :destroy
  
  validates :name, presence: true, uniqueness: { scope: :ekn_id }
  validates :generation_method, presence: true
  validates :status, inclusion: { in: %w[pending active archived] }
  
  enum :status, {
    pending: 'pending',
    active: 'active', 
    archived: 'archived'
  }
  
  enum :generation_method, {
    knowledge_graph: 'knowledge_graph',
    manual: 'manual',
    ai_generated: 'ai_generated'
  }
  
  scope :active, -> { where(status: 'active') }
  scope :for_archetype, ->(archetype) { joins(:training_questions).where(training_questions: { archetype_focus: archetype }) }
  
  # Generate questions from EKN's knowledge graph
  def self.generate_for_ekn(ekn, options = {})
    generator = TrainingQuestionGenerator.new(ekn)
    generator.generate_question_set(options)
  end
  
  # Get questions by type
  def questions_by_type
    training_questions.group(:question_type).count
  end
  
  # Get questions by archetype focus
  def questions_by_archetype
    training_questions.where.not(archetype_focus: nil).group(:archetype_focus).count
  end
  
  # Get questions by difficulty
  def questions_by_difficulty
    training_questions.group(:difficulty_level).count
  end
  
  # Update question count
  def update_question_count!
    update!(question_count: training_questions.count)
  end
  
  # Check if ready for training
  def ready_for_training?
    active? && training_questions.active.any?
  end
  
  # Get summary statistics
  def summary_stats
    {
      total_questions: question_count,
      by_type: questions_by_type,
      by_archetype: questions_by_archetype,
      by_difficulty: questions_by_difficulty,
      avg_score: training_questions.where('avg_score > 0').average(:avg_score)&.round(2) || 0.0,
      times_used: training_runs.count
    }
  end
  
  # Get generation metadata summary
  def generation_summary
    {
      method: generation_method,
      generated_at: created_at,
      knowledge_snapshot: generation_metadata['knowledge_snapshot'],
      node_count: generation_metadata['node_count'],
      relationship_count: generation_metadata['relationship_count'],
      pools_analyzed: generation_metadata['pools_analyzed']
    }
  end
end