class McpToolCall < ApplicationRecord
  include Loggable
  
  belongs_to :ekn
  belongs_to :conversation, optional: true     # Null for external calls (OpenAI Playground, etc.)
  belongs_to :message, optional: true          # Null for external calls (OpenAI Playground, etc.)
  belongs_to :mcp_test_execution, optional: true  # Null for non-test calls
  
  # Status values
  STATUSES = {
    pending: 'pending',
    executing: 'executing',
    completed: 'completed',
    failed: 'failed',
    timeout: 'timeout'
  }.freeze
  
  validates :tool_name, presence: true
  validates :status, inclusion: { in: STATUSES.values }
  
  before_create :set_defaults
  after_create :log_creation
  after_update :log_status_change, if: :saved_change_to_status?
  
  scope :pending, -> { where(status: STATUSES[:pending]) }
  scope :completed, -> { where(status: STATUSES[:completed]) }
  scope :failed, -> { where(status: STATUSES[:failed]) }
  scope :recent, -> { order(created_at: :desc) }
  scope :external_calls, -> { where(is_external_call: true) }
  scope :internal_calls, -> { where(is_external_call: false) }
  scope :by_client, ->(client_name) { where(client_name: client_name) }
  scope :test_calls, -> { where.not(mcp_test_execution_id: nil) }
  scope :non_test_calls, -> { where(mcp_test_execution_id: nil) }
  scope :by_openai_request, ->(request_id) { where(openai_request_id: request_id) }
  
  def execute!
    log_info "Starting execution of #{tool_name} tool (ID: #{tool_id})"
    update!(status: STATUSES[:executing], started_at: Time.current)
  end
  
  def complete!(response_data)
    log_info "Completed #{tool_name} tool call successfully"
    log_debug "Response data: #{response_data.to_json.truncate(500)}"
    update!(
      status: STATUSES[:completed],
      response_data: response_data,
      completed_at: Time.current
    )
  end
  
  def fail!(error_message)
    log_error "Failed #{tool_name} tool call: #{error_message}"
    update!(
      status: STATUSES[:failed],
      error_message: error_message,
      completed_at: Time.current
    )
  end
  
  def duration_ms
    return nil unless started_at && completed_at
    ((completed_at - started_at) * 1000).round
  end
  
  private
  
  def set_defaults
    self.status ||= STATUSES[:pending]
  end
  
  # Check if this is an external call (from OpenAI Playground, etc.)
  def external_call?
    is_external_call?
  end
  
  # Get call context summary
  def call_context
    if test_call?
      "Test execution: #{test_case&.name} (Run ##{test_run&.id})"
    elsif external_call?
      "#{client_name} #{client_version} from #{client_ip}"
    else
      "Internal (Message ##{message_id}, Conversation ##{conversation_id})"
    end
  end
  
  # Check if this tool call is part of a test execution
  def test_call?
    mcp_test_execution_id.present?
  end
  
  # Get the test suite if this is a test call
  def test_suite
    mcp_test_execution&.test_suite
  end
  
  # Get the test case if this is a test call
  def test_case
    mcp_test_execution&.mcp_test_case
  end
  
  # Get the test run if this is a test call
  def test_run
    mcp_test_execution&.mcp_test_run
  end
  
  def log_creation
    if is_external_call?
      log_info "External MCP Tool Call created: #{tool_name} (#{tool_id}) from #{client_name} #{client_version} [#{client_ip}]"
    else
      log_info "Internal MCP Tool Call created: #{tool_name} (#{tool_id}) for message ##{message_id}"
    end
    log_debug "Arguments: #{arguments.to_json}" if arguments.present?
  end
  
  def log_status_change
    log_info "MCP Tool Call #{tool_id} status changed: #{status_before_last_save} -> #{status}"
  end
end
