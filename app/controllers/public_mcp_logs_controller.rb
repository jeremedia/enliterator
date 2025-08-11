# frozen_string_literal: true

# Public controller for viewing intelligent MCP test run logs (for demonstration)
class PublicMcpLogsController < ApplicationController
  def index
    @intelligent_test_runs = McpIntelligentTestRun.includes(:ekn, :mcp_test_case, :mcp_test_run)
                                                 .order(created_at: :desc)
                                                 .limit(50)
    
    # Calculate summary statistics
    @stats = {
      total_runs: @intelligent_test_runs.count,
      average_score: McpIntelligentTestRun.successful.average(:overall_score)&.round(3) || 0.0,
      success_rate: calculate_success_rate(McpIntelligentTestRun.all),
      evaluator_breakdown: McpIntelligentTestRun.group(:evaluator_type).count,
      recent_trend: calculate_recent_trend
    }
    
    @ekns = Ekn.order(:name).limit(10)
    
    render 'admin/mcp_intelligent_test_runs/index'
  end
  
  def show
    @intelligent_test_run = McpIntelligentTestRun.find(params[:id])
    @log_entries = @intelligent_test_run.logs.first&.log_items&.order(:created_at) || []
    
    # Parse evaluation results for display
    @evaluation_details = parse_evaluation_details(@intelligent_test_run.evaluation_results)
    
    # Get related runs for comparison
    @related_runs = McpIntelligentTestRun.where(ekn: @intelligent_test_run.ekn)
                                        .where.not(id: @intelligent_test_run.id)
                                        .order(created_at: :desc)
                                        .limit(5)
    
    render 'admin/mcp_intelligent_test_runs/show'
  end
  
  private
  
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
end