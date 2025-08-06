class PromptVersion < ApplicationRecord
  belongs_to :prompt
  has_many :messages
  has_many :prompt_performances
  
  validates :content, presence: true
  validates :version_number, presence: true, uniqueness: { scope: :prompt_id }
  
  enum status: {
    draft: 0,
    testing: 1,
    active: 2,
    retired: 3
  }
  
  scope :active, -> { where(status: :active) }
  scope :testing, -> { where(status: :testing) }
  scope :current, -> { where(status: [:active, :testing]) }
  
  before_save :extract_variables
  after_create :set_as_current_if_first
  
  # Render the prompt with variable substitution
  def render(variables = {})
    rendered = content.dup
    
    variables.each do |key, value|
      rendered.gsub!(/\{\{#{key}\}\}/, value.to_s)
    end
    
    # Warn about missing variables in development
    if Rails.env.development?
      missing = required_variables - variables.keys.map(&:to_s)
      if missing.any?
        Rails.logger.warn "Missing variables for prompt #{prompt.key}: #{missing.join(', ')}"
      end
    end
    
    rendered
  end
  
  # Variables required by this prompt
  def required_variables
    variables || []
  end
  
  # Calculate performance score based on usage metrics
  def calculate_performance_score
    performances = prompt_performances.recent(100)
    return nil if performances.empty?
    
    satisfaction_weight = 0.4
    completion_weight = 0.4
    time_weight = 0.2
    
    avg_satisfaction = performances.average(:user_satisfaction) || 0
    completion_rate = performances.where(task_completed: true).count.to_f / performances.count
    avg_response_time = performances.average(:response_time) || 0
    
    # Normalize response time (lower is better, assume 2 seconds is good)
    time_score = [1.0, 2.0 / (avg_response_time + 0.01)].min
    
    score = (avg_satisfaction / 5.0 * satisfaction_weight) +
            (completion_rate * completion_weight) +
            (time_score * time_weight)
    
    (score * 100).round(2)
  end
  
  # Promote this version to active
  def promote!
    transaction do
      # Retire other active versions
      prompt.prompt_versions.active.update_all(status: :retired)
      
      # Make this version active
      update!(status: :active)
      
      # Set as current version on prompt
      prompt.update!(current_version: self)
    end
  end
  
  # Start A/B testing against current active version
  def start_ab_test!(percentage: 50)
    raise "Version must be in draft status" unless draft?
    raise "No active version to test against" unless prompt.current_version&.active?
    
    update!(
      status: :testing,
      metadata: (metadata || {}).merge(
        ab_test_percentage: percentage,
        ab_test_started_at: Time.current
      )
    )
  end
  
  private
  
  def extract_variables
    self.variables = content.scan(/\{\{(\w+)\}\}/).flatten.uniq
  end
  
  def set_as_current_if_first
    if prompt.prompt_versions.count == 1
      prompt.update!(current_version: self)
      update!(status: :active)
    end
  end
end