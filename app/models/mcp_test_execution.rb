# frozen_string_literal: true

# MCP Test Execution - Individual test case execution result
#
# Represents the execution of a single test case within a test run.
# Links to actual MCP tool calls and stores execution metrics and validation results.
#
# Example execution_metrics:
# {
#   "response_time_ms": 2340,
#   "tools_called_count": 3,
#   "openai_request_id": "req_abc123",
#   "total_tokens_used": 1250
# }
#
# Example assertion_results:
# {
#   "correct_tools_called": true,
#   "expected_tools": ["search", "fetch"],
#   "actual_tools": ["search", "fetch"],
#   "response_quality_score": 0.87,
#   "correct_ekn_targeted": true,
#   "min_results_met": true,
#   "response_time_within_threshold": true
# }
#
class McpTestExecution < ApplicationRecord
  belongs_to :mcp_test_run
  belongs_to :mcp_test_case
  has_many :mcp_tool_calls, dependent: :nullify
  
  enum :status, { 
    pending: 0, 
    running: 1, 
    completed: 2, 
    failed: 3 
  }, prefix: :status
  
  validates :mcp_test_run_id, uniqueness: { scope: :mcp_test_case_id }
  validates :status, presence: true
  
  # JSON field accessors with default values
  attribute :execution_metrics, :json, default: {}
  attribute :assertion_results, :json, default: {}
  
  scope :recent, -> { order(created_at: :desc) }
  scope :passed, -> { where(status: :completed) }
  scope :failed_executions, -> { where(status: :failed) }
  scope :by_test_case, ->(test_case) { where(mcp_test_case: test_case) }
  scope :by_test_run, ->(test_run) { where(mcp_test_run: test_run) }
  
  # Start the execution
  def start!
    update!(
      status: :running,
      started_at: Time.current
    )
  end
  
  # Complete the execution with results
  def complete!(metrics = {}, assertions = {})
    update!(
      status: :completed,
      completed_at: Time.current,
      execution_metrics: metrics,
      assertion_results: assertions
    )
  end
  
  # Fail the execution
  def fail!(error_msg = nil, partial_metrics = {})
    update!(
      status: :failed,
      completed_at: Time.current,
      error_message: error_msg,
      execution_metrics: partial_metrics
    )
  end
  
  # Get execution duration in milliseconds
  def duration_ms
    return nil unless started_at && completed_at
    ((completed_at - started_at) * 1000).round
  end
  
  # Get response time from metrics
  def response_time_ms
    execution_metrics&.dig("response_time_ms")
  end
  
  # Check if all assertions passed
  def all_assertions_passed?
    return false unless assertion_results.present?
    
    # Check common assertion fields
    checks = %w[
      correct_tools_called
      correct_ekn_targeted
      min_results_met
      response_time_within_threshold
    ]
    
    checks.all? { |check| assertion_results[check] == true }
  end
  
  # Get quality score
  def quality_score
    assertion_results&.dig("response_quality_score") || 0.0
  end
  
  # Get expected vs actual tools comparison
  def tools_comparison
    {
      expected: assertion_results&.dig("expected_tools") || [],
      actual: assertion_results&.dig("actual_tools") || [],
      matched: assertion_results&.dig("correct_tools_called") == true
    }
  end
  
  # Get summary of execution results
  def execution_summary
    {
      status: status,
      duration_ms: duration_ms,
      response_time_ms: response_time_ms,
      quality_score: quality_score,
      all_assertions_passed: all_assertions_passed?,
      tools_called_count: execution_metrics&.dig("tools_called_count") || 0,
      error: error_message
    }
  end
  
  # Check if execution is in progress
  def in_progress?
    status_running?
  end
  
  # Get formatted duration
  def formatted_duration
    return "N/A" unless duration_ms
    
    if duration_ms < 1000
      "#{duration_ms}ms"
    else
      "#{(duration_ms / 1000.0).round(1)}s"
    end
  end
  
  # Get the test suite through the run
  def test_suite
    mcp_test_run.mcp_test_suite
  end
  
  def to_s
    "#{test_suite.name} - #{mcp_test_case.name} (Run ##{mcp_test_run.id})"
  end
end