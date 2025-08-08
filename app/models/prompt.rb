# == Schema Information
#
# Table name: prompts
#
#  id                 :bigint           not null, primary key
#  key                :string
#  name               :string
#  description        :text
#  category           :integer
#  context            :integer
#  active             :boolean
#  current_version_id :integer
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#
# Indexes
#
#  index_prompts_on_key  (key) UNIQUE
#
class Prompt < ApplicationRecord
  has_many :prompt_versions, dependent: :destroy
  belongs_to :current_version, class_name: 'PromptVersion', optional: true
  
  validates :key, presence: true, uniqueness: true
  validates :name, presence: true
  
  # Categories for different types of prompts
  enum :category, {
    system: 0,        # Core system prompts
    interview: 1,     # Data collection prompts
    pipeline: 2,      # Pipeline operation prompts
    analysis: 3,      # Analysis and insights
    explanation: 4,   # Explaining concepts
    error: 5,         # Error handling
    coaching: 6       # User guidance
  }
  
  # Context where prompts are used
  enum :context, {
    global: 0,        # Used everywhere
    intake: 1,        # Stage 1 specific
    rights: 2,        # Stage 2 specific
    lexicon: 3,       # Stage 3 specific
    pools: 4,         # Stage 4 specific
    graph: 5,         # Stage 5 specific
    embeddings: 6,    # Stage 6 specific
    literacy: 7,      # Stage 7 specific
    deliverables: 8,  # Stage 8 specific
    conversation: 9   # General conversation
  }
  
  scope :active, -> { where(active: true) }
  scope :by_category, ->(cat) { where(category: cat) }
  scope :by_context, ->(ctx) { where(context: ctx) }
  
  # Get the current active version or create a default one
  def active_version
    current_version || prompt_versions.active.first || create_default_version
  end
  
  # Render the prompt with variables
  def render(variables = {})
    active_version.render(variables)
  end
  
  # Create a new version of this prompt
  def create_version(content, status: :draft)
    version_number = prompt_versions.maximum(:version_number).to_i + 1
    
    prompt_versions.create!(
      content: content,
      status: status,
      version_number: version_number,
      variables: extract_variables(content)
    )
  end
  
  # Performance metrics across all versions
  def performance_metrics
    {
      total_uses: prompt_versions.joins(:messages).count,
      avg_satisfaction: prompt_versions.joins(:prompt_performances)
                                       .average('prompt_performances.user_satisfaction'),
      completion_rate: calculate_completion_rate,
      active_version_score: current_version&.performance_score
    }
  end
  
  private
  
  def create_default_version
    create_version(
      "Default prompt for #{name}. Please update with appropriate content.",
      status: :draft
    )
  end
  
  def extract_variables(content)
    content.scan(/\{\{(\w+)\}\}/).flatten.uniq
  end
  
  def calculate_completion_rate
    # Calculate based on PromptPerformance records
    total = prompt_versions.joins(:prompt_performances).count
    return 0 if total == 0
    
    completed = prompt_versions.joins(:prompt_performances)
                               .where(prompt_performances: { task_completed: true })
                               .count
    
    (completed.to_f / total * 100).round(2)
  end
end
