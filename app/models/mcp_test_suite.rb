# frozen_string_literal: true

# MCP Test Suite - Configuration for a suite of related tests
#
# Manages test suite configuration using OpenAI saved prompts with variables.
# Each suite defines base variables that can be overridden by individual test cases.
#
# Example base_variables:
# {
#   "SYSTEM_PROMPT": "You are testing EKN {EKN_ID}. Use tools {TOOL_SEQUENCE} for '{QUERY}'.",
#   "EKN_ID": "34",
#   "TOOL_SEQUENCE": "search"
# }
#
# Example test_config:
# {
#   "timeout": 30,
#   "max_retries": 3,
#   "concurrent_executions": 5
# }
#
class McpTestSuite < ApplicationRecord
  has_many :mcp_test_cases, dependent: :destroy
  has_many :mcp_test_runs, dependent: :destroy
  
  validates :name, presence: true, uniqueness: true
  validates :saved_prompt_id, presence: true, format: { with: /\Apmpt_[a-zA-Z0-9_-]+\z/, message: "must be a valid OpenAI prompt ID (pmpt_xxx)" }
  
  # JSON field accessors with default values
  attribute :base_variables, :json, default: {}
  attribute :test_config, :json, default: {}
  
  scope :enabled, -> { joins(:mcp_test_cases).where(mcp_test_cases: { enabled: true }).distinct }
  scope :recent, -> { order(updated_at: :desc) }
  
  # Get the total number of enabled test cases
  def enabled_test_cases_count
    mcp_test_cases.where(enabled: true).count
  end
  
  # Get the most recent test run
  def latest_test_run
    mcp_test_runs.order(created_at: :desc).first
  end
  
  # Get test configuration with defaults
  def effective_test_config
    {
      "timeout" => 30,
      "max_retries" => 3,
      "concurrent_executions" => 5
    }.merge(test_config || {})
  end
  
  # Merge base variables with case-specific overrides
  def merged_variables(case_overrides = {})
    (base_variables || {}).merge(case_overrides || {})
  end
  
  # Check if suite is ready to run
  def ready_to_run?
    saved_prompt_id.present? && enabled_test_cases_count > 0
  end
  
  def to_s
    name
  end
end