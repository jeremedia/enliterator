# frozen_string_literal: true

# MCP Test Case - Individual test scenario within a suite
#
# Represents a specific test scenario with variable overrides and expected outcomes.
# Variables are merged with the parent suite's base_variables.
#
# Example variable_overrides:
# {
#   "EKN_ID": "39",
#   "QUERY": "renewable energy processes",
#   "TOOL_SEQUENCE": "search,fetch,bridge"
# }
#
# Example expectations:
# {
#   "tools_called": ["search", "fetch", "bridge"],
#   "min_results": 5,
#   "max_response_time_ms": 5000,
#   "required_ekn_id": "39"
# }
#
class McpTestCase < ApplicationRecord
  belongs_to :mcp_test_suite
  has_many :mcp_test_executions, dependent: :destroy
  has_many :mcp_test_runs, through: :mcp_test_executions
  
  validates :name, presence: true, uniqueness: { scope: :mcp_test_suite_id }
  
  # JSON field accessors with default values
  attribute :variable_overrides, :json, default: {}
  attribute :expectations, :json, default: {}
  
  scope :enabled, -> { where(enabled: true) }
  scope :disabled, -> { where(enabled: false) }
  scope :recent, -> { order(updated_at: :desc) }
  scope :by_suite, ->(suite) { where(mcp_test_suite: suite) }
  
  # Get the merged variables for this test case
  def effective_variables
    mcp_test_suite.merged_variables(variable_overrides)
  end
  
  # Get expectations with defaults
  def effective_expectations
    {
      "tools_called" => [],
      "min_results" => 1,
      "max_response_time_ms" => 30000
    }.merge(expectations || {})
  end
  
  # Get the most recent execution
  def latest_execution
    mcp_test_executions.order(created_at: :desc).first
  end
  
  # Get success rate (percentage of passing executions)
  def success_rate
    total = mcp_test_executions.count
    return 0.0 if total.zero?
    
    passed = mcp_test_executions.where(status: 'completed').count
    (passed.to_f / total * 100).round(1)
  end
  
  # Check if this case has been executed recently
  def executed_recently?(hours = 24)
    latest_execution&.created_at&.> hours.hours.ago
  end
  
  # Get expected EKN ID from variables
  def expected_ekn_id
    effective_variables["EKN_ID"]
  end
  
  # Get expected query from variables
  def expected_query
    effective_variables["QUERY"]
  end
  
  # Get expected tool sequence
  def expected_tools
    tool_sequence = effective_variables["TOOL_SEQUENCE"]
    return [] if tool_sequence.blank?
    
    tool_sequence.split(",").map(&:strip)
  end
  
  def to_s
    "#{mcp_test_suite.name} - #{name}"
  end
end