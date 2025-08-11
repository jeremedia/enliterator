# frozen_string_literal: true

# Admin controller for viewing intelligent MCP test run logs and analysis
class Admin::McpIntelligentTestRunsController < Admin::BaseController
  before_action :set_intelligent_test_run, only: [:show]
  
  def index
    @intelligent_test_runs = McpIntelligentTestRun.includes(:ekn, :mcp_test_case, :mcp_test_run)
                                                 .order(created_at: :desc)
                                                 .limit(50)
    
    # Filter by EKN if specified
    if params[:ekn_id].present?
      @intelligent_test_runs = @intelligent_test_runs.where(ekn_id: params[:ekn_id])
    end
    
    # Filter by evaluator type if specified
    if params[:evaluator_type].present?
      @intelligent_test_runs = @intelligent_test_runs.where(evaluator_type: params[:evaluator_type])
    end
    
    # Filter by status if specified
    if params[:status].present?
      @intelligent_test_runs = @intelligent_test_runs.where(status: params[:status])
    end
    
    # Calculate summary statistics using base scope
    base_scope = McpIntelligentTestRun.all
    if params[:ekn_id].present?
      base_scope = base_scope.where(ekn_id: params[:ekn_id])
    end
    if params[:evaluator_type].present?
      base_scope = base_scope.where(evaluator_type: params[:evaluator_type])
    end
    if params[:status].present?
      base_scope = base_scope.where(status: params[:status])
    end
    
    @stats = {
      total_runs: base_scope.count,
      average_score: base_scope.successful.average(:overall_score)&.round(3) || 0.0,
      success_rate: calculate_success_rate(base_scope),
      evaluator_breakdown: base_scope.group(:evaluator_type).count,
      recent_trend: calculate_recent_trend
    }
    
    @ekns = Ekn.order(:name)
  end
  
  def show
    @log_entries = @intelligent_test_run.logs.first&.log_items&.order(:created_at) || []
    
    # Parse evaluation results for display
    @evaluation_details = parse_evaluation_details(@intelligent_test_run.evaluation_results)
    
    # Get related runs for comparison
    @related_runs = McpIntelligentTestRun.where(ekn: @intelligent_test_run.ekn)
                                        .where.not(id: @intelligent_test_run.id)
                                        .order(created_at: :desc)
                                        .limit(5)
  end
  
  def analytics
    @ekn_performance = calculate_ekn_performance
    @evaluator_performance = calculate_evaluator_performance
    @performance_trends = calculate_performance_trends
    @recent_insights = extract_recent_insights
  end
  
  private
  
  def set_intelligent_test_run
    @intelligent_test_run = McpIntelligentTestRun.find(params[:id])
  end
  
  def calculate_success_rate(runs)
    return 0.0 if runs.empty?
    
    successful_count = runs.successful.count
    (successful_count.to_f / runs.count * 100).round(1)
  end
  
  def calculate_recent_trend
    recent_runs = McpIntelligentTestRun.where(created_at: 7.days.ago..)
                                      .successful
                                      .includes(:ekn)
    
    return {} if recent_runs.empty?
    
    # Group by day and calculate average scores
    trend_data = recent_runs.to_a
                           .group_by { |run| run.created_at.to_date }
                           .transform_values { |runs| runs.sum(&:overall_score) / runs.size }
                           .sort_by { |date, _| date }
                           .last(7)
    
    Hash[trend_data]
  end
  
  def parse_evaluation_details(results)
    return {} unless results.present?
    
    if results.is_a?(String)
      begin
        results = JSON.parse(results)
      rescue JSON::ParserError
        return {}
      end
    end
    
    results || {}
  end
  
  def calculate_ekn_performance
    McpIntelligentTestRun.successful
                        .joins(:ekn)
                        .group('ekns.name', 'ekns.slug')
                        .group(:ekn_id)
                        .average(:overall_score)
                        .map do |(name, slug, ekn_id), avg_score|
      {
        ekn_id: ekn_id,
        name: name,
        slug: slug,
        average_score: avg_score.round(3),
        run_count: McpIntelligentTestRun.where(ekn_id: ekn_id).count
      }
    end.sort_by { |data| -data[:average_score] }
  end
  
  def calculate_evaluator_performance
    McpIntelligentTestRun.group(:evaluator_type)
                        .group(:status)
                        .count
                        .each_with_object({}) do |((evaluator, status), count), result|
      result[evaluator] ||= {}
      result[evaluator][status] = count
    end
  end
  
  def calculate_performance_trends
    # Last 30 days of performance data
    runs_by_date = McpIntelligentTestRun.where(created_at: 30.days.ago..)
                                       .successful
                                       .group_by { |run| run.created_at.to_date }
                                       .transform_values { |runs| runs.sum(&:overall_score) / runs.size }
                                       .sort_by { |date, _| date }
    
    Hash[runs_by_date]
  end
  
  def extract_recent_insights
    recent_runs = McpIntelligentTestRun.includes(:ekn)
                                      .where(created_at: 7.days.ago..)
                                      .order(created_at: :desc)
                                      .limit(10)
    
    insights = []
    
    # Low scoring EKNs
    low_scorers = recent_runs.select { |run| run.overall_score && run.overall_score < 0.6 }
    if low_scorers.any?
      insights << {
        type: 'warning',
        title: 'Low Performing EKNs',
        message: "#{low_scorers.count} EKNs scored below 60% recently",
        details: low_scorers.map { |run| "#{run.ekn.name}: #{(run.overall_score * 100).round}%" }
      }
    end
    
    # High performing EKNs
    high_scorers = recent_runs.select { |run| run.overall_score && run.overall_score >= 0.8 }
    if high_scorers.any?
      insights << {
        type: 'success',
        title: 'High Performing EKNs',
        message: "#{high_scorers.count} EKNs scored 80% or higher",
        details: high_scorers.map { |run| "#{run.ekn.name}: #{(run.overall_score * 100).round}%" }
      }
    end
    
    # Evaluator reliability
    evaluator_stats = recent_runs.group_by(&:evaluator_type)
                                .transform_values { |runs| runs.count { |r| r.status == 'completed' } }
    
    insights << {
      type: 'info',
      title: 'Evaluator Performance',
      message: 'Recent evaluator reliability',
      details: evaluator_stats.map { |type, completed| "#{type}: #{completed} completed" }
    }
    
    insights
  end
end