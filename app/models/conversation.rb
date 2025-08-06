class Conversation < ApplicationRecord
  has_many :messages, dependent: :destroy
  # User association removed - can be added later when user management is implemented
  belongs_to :ingest_batch, optional: true
  
  # Store conversation context and state
  store_accessor :context, :current_dataset, :current_stage, :user_expertise_level, 
                 :preferred_detail_level, :session_goals, :domain_context
  
  # CRITICAL: Store model configuration for this conversation
  # This allows per-conversation tuning and experimentation
  store_accessor :model_config, :model_name, :temperature, :max_tokens, 
                 :top_p, :frequency_penalty, :presence_penalty, :response_format,
                 :tools_enabled, :custom_instructions
  
  validates :status, presence: true
  
  before_create :set_default_model_config
  before_create :set_initial_status
  
  # Conversation statuses
  enum status: {
    active: 0,
    paused: 1,
    completed: 2,
    abandoned: 3
  }
  
  # User expertise levels
  enum expertise_level: {
    beginner: 0,
    intermediate: 1,
    advanced: 2,
    expert: 3
  }
  
  scope :recent, -> { order(last_activity_at: :desc) }
  scope :active, -> { where(status: :active) }
  # for_user scope removed - can be added later when user management is implemented
  
  # Get or set the OpenAI model for this conversation
  def ai_model
    model_name || default_model
  end
  
  def ai_model=(model)
    self.model_name = model
  end
  
  # Get complete model configuration for OpenAI calls
  def model_configuration
    {
      model: ai_model,
      temperature: (temperature || default_temperature).to_f,
      max_tokens: (max_tokens || default_max_tokens).to_i,
      top_p: (top_p || 1.0).to_f,
      frequency_penalty: (frequency_penalty || 0.0).to_f,
      presence_penalty: (presence_penalty || 0.0).to_f,
      response_format: response_format || { type: "text" }
    }.compact
  end
  
  # Update model config with validation
  def update_model_config(config = {})
    config.each do |key, value|
      case key.to_sym
      when :model_name
        validate_model_name(value)
        self.model_name = value
      when :temperature
        validate_temperature(value)
        self.temperature = value
      when :max_tokens
        validate_max_tokens(value)
        self.max_tokens = value
      when :top_p
        validate_top_p(value)
        self.top_p = value
      when :tools_enabled
        self.tools_enabled = value
      when :custom_instructions
        self.custom_instructions = value
      end
    end
    save!
  end
  
  # Set configuration based on conversation type
  def configure_for_intent(intent_type)
    case intent_type
    when :creative, :brainstorming
      self.temperature = 0.9
      self.top_p = 0.95
      self.model_name = "gpt-4o"
    when :analysis, :technical
      self.temperature = 0.3
      self.top_p = 0.9
      self.model_name = "gpt-4o"
    when :extraction, :structured
      self.temperature = 0.0
      self.model_name = "gpt-4o-2024-08-06"  # Structured outputs model
      self.response_format = { type: "json_schema", strict: true }
    when :conversation, :chat
      self.temperature = 0.7
      self.model_name = "gpt-4o-mini"  # Faster, cheaper for general chat
    else
      set_default_model_config
    end
  end
  
  # Add a message to the conversation
  def add_message(role:, content:, metadata: {})
    message = messages.create!(
      role: role,
      content: content,
      metadata: metadata
    )
    
    touch(:last_activity_at)
    message
  end
  
  # Get conversation summary for context
  def summary
    {
      id: id,
      status: status,
      messages_count: messages.count,
      recent_messages: messages.recent(5).map { |m| 
        { role: m.role, content: m.content.truncate(100) }
      },
      current_dataset: current_dataset,
      current_stage: current_stage,
      user_level: expertise_level || 'intermediate',
      model_config: model_configuration,
      goals: session_goals,
      domain: domain_context
    }
  end
  
  # Build context for OpenAI calls
  def build_context(include_history: true, history_limit: 10)
    context = {
      conversation_id: id,
      user_expertise: expertise_level || 'intermediate',
      detail_level: preferred_detail_level || 'balanced',
      current_dataset: current_dataset,
      current_stage: current_stage,
      domain: domain_context
    }
    
    if include_history
      context[:message_history] = messages
        .recent(history_limit)
        .map { |m| { role: m.role, content: m.content } }
    end
    
    context
  end
  
  # Check if conversation should use specific model features
  def use_structured_outputs?
    response_format&.dig("type") == "json_schema"
  end
  
  def use_function_calling?
    tools_enabled == true || tools_enabled == "true"
  end
  
  def use_vision?
    model_name&.include?("vision") || model_name&.include?("gpt-4o")
  end
  
  private
  
  def set_default_model_config
    self.model_name ||= default_model
    self.temperature ||= default_temperature
    self.max_tokens ||= default_max_tokens
    self.top_p ||= 1.0
    self.frequency_penalty ||= 0.0
    self.presence_penalty ||= 0.0
    self.tools_enabled ||= false
  end
  
  def set_initial_status
    self.status ||= :active
    self.last_activity_at ||= Time.current
  end
  
  def default_model
    ENV.fetch('OPENAI_DEFAULT_MODEL', 'gpt-4o-mini')
  end
  
  def default_temperature
    ENV.fetch('OPENAI_DEFAULT_TEMPERATURE', '0.7').to_f
  end
  
  def default_max_tokens
    ENV.fetch('OPENAI_DEFAULT_MAX_TOKENS', '2000').to_i
  end
  
  def validate_model_name(model)
    valid_models = [
      'gpt-4o', 
      'gpt-4o-2024-08-06',
      'gpt-4o-mini',
      'gpt-4-turbo',
      'gpt-3.5-turbo',
      'o1-preview',
      'o1-mini'
    ]
    
    unless valid_models.include?(model)
      raise ArgumentError, "Invalid model: #{model}. Valid models: #{valid_models.join(', ')}"
    end
  end
  
  def validate_temperature(temp)
    temp = temp.to_f
    unless temp >= 0.0 && temp <= 2.0
      raise ArgumentError, "Temperature must be between 0.0 and 2.0"
    end
  end
  
  def validate_max_tokens(tokens)
    tokens = tokens.to_i
    unless tokens > 0 && tokens <= 128000  # GPT-4o max
      raise ArgumentError, "Max tokens must be between 1 and 128000"
    end
  end
  
  def validate_top_p(p)
    p = p.to_f
    unless p > 0.0 && p <= 1.0
      raise ArgumentError, "Top-p must be between 0.0 and 1.0"
    end
  end
end
