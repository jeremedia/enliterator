# frozen_string_literal: true

# MCP Test Run - Execution session of a test suite
#
# Represents a single execution of a test suite, containing multiple test case executions.
# Tracks overall status and aggregated metrics for the entire run.
#
# Example summary_metrics:
# {
#   "total_cases": 12,
#   "passed": 10,
#   "failed": 2,
#   "avg_response_time_ms": 2340,
#   "total_tool_calls": 36,
#   "unique_tools_used": ["search", "fetch", "bridge"],
#   "total_duration_ms": 28080
# }
#
class McpTestRun < ApplicationRecord
  belongs_to :mcp_test_suite
  has_many :mcp_test_executions, dependent: :destroy
  has_many :mcp_test_cases, through: :mcp_test_executions
  has_many :mcp_tool_calls, through: :mcp_test_executions
  has_many :mcp_intelligent_test_runs, dependent: :destroy
  
  enum :status, { 
    pending: 0, 
    running: 1, 
    completed: 2, 
    failed: 3 
  }, prefix: :status
  
  validates :status, presence: true
  
  # JSON field accessor with default value
  attribute :summary_metrics, :json, default: {}
  
  scope :recent, -> { order(created_at: :desc) }
  scope :successful, -> { where(status: :completed) }
  scope :failed_runs, -> { where(status: :failed) }
  
  # Start the test run
  def start!
    update!(
      status: :running,
      started_at: Time.current,
      summary_metrics: { "started_at" => Time.current.iso8601 }
    )
  end
  
  # Complete the test run with success
  def complete!
    calculate_summary_metrics
    update!(
      status: :completed,
      completed_at: Time.current
    )
  end
  
  # Mark the test run as failed
  def fail!(error_msg = nil)
    calculate_summary_metrics
    update!(
      status: :failed,
      completed_at: Time.current,
      error_message: error_msg
    )
  end
  
  # Get total duration in milliseconds
  def duration_ms
    return nil unless started_at && completed_at
    ((completed_at - started_at) * 1000).round
  end
  
  # Get success rate for this run
  def success_rate
    total = mcp_test_executions.count
    return 0.0 if total.zero?
    
    passed = mcp_test_executions.where(status: 'completed').count
    (passed.to_f / total * 100).round(1)
  end
  
  # Check if run is in progress
  def in_progress?
    status_running?
  end
  
  # Get formatted duration
  def formatted_duration
    return "N/A" unless duration_ms
    
    seconds = duration_ms / 1000.0
    if seconds < 60
      "#{seconds.round(1)}s"
    else
      minutes = seconds / 60
      "#{minutes.round(1)}m"
    end
  end
  
  private
  
  # Calculate and update summary metrics
  def calculate_summary_metrics
    executions = mcp_test_executions.includes(:mcp_test_case)
    
    metrics = {
      "total_cases" => executions.count,
      "passed" => executions.where(status: 'completed').count,
      "failed" => executions.where(status: 'failed').count,
      "pending" => executions.where(status: 'pending').count,
      "avg_response_time_ms" => calculate_avg_response_time(executions),
      "total_tool_calls" => count_total_tool_calls(executions),
      "unique_tools_used" => extract_unique_tools(executions),
      "total_duration_ms" => duration_ms,
      "completed_at" => Time.current.iso8601
    }
    
    self.summary_metrics = (summary_metrics || {}).merge(metrics)
  end
  
  def calculate_avg_response_time(executions)
    completed = executions.select { |e| e.execution_metrics.present? && e.execution_metrics["response_time_ms"] }
    return 0 if completed.empty?
    
    total_time = completed.sum { |e| e.execution_metrics["response_time_ms"] }
    (total_time.to_f / completed.size).round
  end
  
  def count_total_tool_calls(executions)
    executions.sum { |e| e.execution_metrics&.dig("tools_called_count") || 0 }
  end
  
  def extract_unique_tools(executions)
    tools = Set.new
    executions.each do |execution|
      if execution.assertion_results&.dig("tools_called")
        tools.merge(execution.assertion_results["tools_called"])
      end
    end
    tools.to_a.sort
  end
end