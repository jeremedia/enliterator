# frozen_string_literal: true

# McpIntelligentTestRun - Detailed logging and tracking for intelligent EKN evaluation
#
# This model provides rich database-backed logging for the intelligent evaluation
# process, tracking each step of EKN personality assessment and meta-creation
# evaluation. Includes full audit trail and performance metrics.
#
class McpIntelligentTestRun < ApplicationRecord
  include Loggable  # Provides rich database-backed logging capabilities
  
  # Associations
  belongs_to :mcp_test_run
  belongs_to :mcp_test_case
  belongs_to :ekn
  
  # Enums for status tracking
  enum :status, {
    pending: 'pending',
    running: 'running', 
    completed: 'completed',
    failed: 'failed',
    timeout: 'timeout'
  }, validate: true
  
  enum :evaluator_type, {
    claude_code_api: 'claude_code_api',
    openai_proxy: 'openai_proxy', 
    fallback: 'fallback'
  }, validate: true
  
  # Validations
  validates :evaluator_type, presence: true
  validates :status, presence: true
  validates :started_at, presence: true, if: :running?
  validates :completed_at, presence: true, if: :completed?
  validates :error_message, presence: true, if: :failed?
  validates :overall_score, presence: true, 
            numericality: { in: 0.0..1.0 }, if: :completed?
  
  # Scopes
  scope :by_evaluator, ->(type) { where(evaluator_type: type) }
  scope :successful, -> { where(status: 'completed') }
  scope :recent, -> { where(created_at: 1.week.ago..) }
  scope :for_ekn, ->(ekn) { where(ekn: ekn) }
  scope :with_scores_above, ->(threshold) { where('overall_score >= ?', threshold) }
  
  # Lifecycle management methods
  def start!(evaluator_type, context = {})
    update!(
      evaluator_type: evaluator_type,
      status: :running,
      started_at: Time.current,
      agent_context: context
    )
    
    log_info "Started intelligent evaluation using #{evaluator_type}"
    log_info "Evaluation context: #{context.keys.join(', ')}"
  end
  
  def complete!(results, score)
    duration = started_at ? ((Time.current - started_at) * 1000).round : nil
    
    update!(
      status: :completed,
      completed_at: Time.current,
      evaluation_results: results,
      overall_score: score,
      duration_ms: duration
    )
    
    log_info "Evaluation completed with score: #{score}"
    log_info "Total duration: #{duration}ms" if duration
  end
  
  def fail!(error_message, context = {})
    duration = started_at ? ((Time.current - started_at) * 1000).round : nil
    
    update!(
      status: :failed,
      completed_at: Time.current,
      error_message: error_message,
      duration_ms: duration,
      performance_metrics: context
    )
    
    log_error "Evaluation failed: #{error_message}"
    log_error "Failure context: #{context}" if context.present?
  end
  
  def timeout!(timeout_seconds)
    duration = started_at ? ((Time.current - started_at) * 1000).round : nil
    
    update!(
      status: :timeout,
      completed_at: Time.current,
      error_message: "Evaluation timed out after #{timeout_seconds}s",
      duration_ms: duration
    )
    
    log_warn "Evaluation timed out after #{timeout_seconds}s"
  end
  
  # Analysis methods
  def personality_authenticity_score
    evaluation_results&.dig('personality_authenticity', 'score')
  end
  
  def framework_compliance_score
    evaluation_results&.dig('framework_compliance', 'score')
  end
  
  def key_findings
    evaluation_results&.dig('key_findings') || []
  end
  
  def recommendations
    evaluation_results&.dig('recommendations') || []
  end
  
  def success_rate
    return 0.0 unless completed?
    overall_score || 0.0
  end
  
  def evaluation_summary
    return "Evaluation pending" if pending?
    return "Evaluation running" if running?
    return "Evaluation failed: #{error_message}" if failed? || timeout?
    
    "Score: #{overall_score} (#{(overall_score * 100).round}%)"
  end
  
  # Class methods for analysis
  def self.average_score_for_ekn(ekn)
    successful.for_ekn(ekn).average(:overall_score) || 0.0
  end
  
  def self.evaluator_performance_stats
    group(:evaluator_type).group(:status).count
  end
  
  def self.recent_performance_trend(days = 7)
    recent_runs = where(created_at: days.days.ago..)
                   .successful
                   .group_by_day(:completed_at)
                   .average(:overall_score)
    
    recent_runs.transform_values { |score| score&.round(3) || 0.0 }
  end
end
