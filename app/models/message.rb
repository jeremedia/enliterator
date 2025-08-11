# == Schema Information
#
# Table name: messages
#
#  id              :bigint           not null, primary key
#  conversation_id :bigint           not null
#  role            :integer
#  content         :text
#  metadata        :jsonb
#  tokens_used     :integer
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#
# Indexes
#
#  index_messages_on_conversation_id  (conversation_id)
#
class Message < ApplicationRecord

  include Loggable

  belongs_to :conversation
  belongs_to :prompt_version, optional: true
  has_many :mcp_tool_calls, dependent: :destroy
  
  validates :role, presence: true
  validates :content, presence: true, unless: :streaming?
  
  # Message roles
  enum :role, { 
    user: 0, 
    assistant: 1, 
    system: 2,
    function: 3,     # Function calling results
    tool: 4          # Tool usage results
  }
  
  # Store rich metadata about the message
  store_accessor :metadata, :intent, :actions_taken, :entities_mentioned,
                 :model_used, :temperature_used, :prompt_key, :confidence_score,
                 :reasoning_trace, :tools_called, :execution_time, :streaming,
                 :error, :error_message, :error_class, :error_backtrace
  
  scope :recent, ->(limit = 10) { order(created_at: :desc).limit(limit) }
  scope :by_role, ->(role) { where(role: role) }
  scope :with_intent, ->(intent) { where("metadata->>'intent' = ?", intent) }
  
  after_create :update_conversation_activity
  after_create :track_token_usage
  after_create :log_message_creation

  def log_message_creation
    # Skip logging if conversation not persisted to avoid ActiveRecord errors
    return unless conversation&.persisted?
    log_info "Message created for conversation #{conversation_id} by #{role} at #{created_at}"
  end
  
  # Track which model configuration was actually used for this message
  def record_model_config(config)
    self.model_used = config[:model]
    self.temperature_used = config[:temperature]
    save!
  end
  
  # Record the prompt that generated this message
  def record_prompt_usage(prompt_version)
    self.prompt_version = prompt_version
    self.prompt_key = prompt_version.prompt.key
    save!
  end
  
  # Record reasoning trace for explainability
  def record_reasoning(trace)
    self.reasoning_trace = trace
    save!
  end
  
  # Record confidence in the response
  def record_confidence(score)
    self.confidence_score = score
    save!
  end
  
  # Check if this message triggered any pipeline actions
  def triggered_actions?
    actions_taken.present? && actions_taken.any?
  end
  
  # Get a summary of this message for context building
  def summary
    {
      role: role,
      content: content.truncate(200),
      intent: intent,
      entities: entities_mentioned,
      actions: actions_taken,
      timestamp: created_at
    }
  end
  
  # Estimate tokens (rough approximation)
  def estimate_tokens
    # Rough estimate: 1 token ≈ 4 characters
    return 0 if content.nil?
    (content.length / 4.0).ceil
  end
  
  # Check if message is currently streaming
  def streaming?
    streaming == true || streaming == 'true'
  end
  
  # Check if message had an error
  def error?
    error == true || error == 'true'
  end
  
  # Check if message used MCP tools
  def used_mcp_tools?
    mcp_tool_calls.any? || metadata&.dig('tool_calls').present?
  end
  
  # Get all MCP tool names used
  def mcp_tool_names
    names = mcp_tool_calls.pluck(:tool_name)
    names += (metadata&.dig('tool_calls') || []).map { |tc| tc['name'] }
    names.uniq.compact
  end
  
  private
  
  def update_conversation_activity
    conversation.touch(:last_activity_at)
  end
  
  def track_token_usage
    return unless tokens_used.nil?
    
    # If not explicitly set, estimate
    self.tokens_used = estimate_tokens
    save!
  end
end
