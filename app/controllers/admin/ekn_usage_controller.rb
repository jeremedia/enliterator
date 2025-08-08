# frozen_string_literal: true

module Admin
  # Controller for viewing API usage analytics per EKN
  class EknUsageController < Admin::BaseController
    before_action :set_ekn, only: [:show]
    
    def index
      @ekns = Ekn.includes(:api_calls)
                 .order(:name)
      
      # Calculate usage summary for each EKN
      @ekn_summaries = @ekns.map do |ekn|
        {
          ekn: ekn,
          total_calls: ekn.api_calls.count,
          total_cost: ekn.api_calls.sum(:total_cost).to_f.round(4),
          total_tokens: ekn.api_calls.sum(:total_tokens),
          last_call: ekn.api_calls.maximum(:created_at),
          success_rate: calculate_success_rate(ekn.api_calls)
        }
      end
      
      # Overall statistics
      @total_stats = {
        total_ekns: @ekns.count,
        total_calls: ApiCall.count,
        total_cost: ApiCall.sum(:total_cost).to_f.round(4),
        calls_with_ekn: ApiCall.where.not(ekn_id: nil).count,
        calls_without_ekn: ApiCall.without_ekn.count
      }
    end
    
    def show
      # Usage summary for specific EKN
      @usage_summary = @ekn.api_usage_summary(:all_time)
      @usage_today = @ekn.api_usage_summary(:today)
      @usage_this_week = @ekn.api_usage_summary(:this_week)
      @usage_this_month = @ekn.api_usage_summary(:this_month)
      
      # Cost breakdown
      @cost_breakdown = @ekn.api_cost_breakdown
      
      # Most expensive calls
      @expensive_calls = @ekn.most_expensive_calls(10)
      
      # Usage by pipeline stage
      @usage_by_stage = @ekn.api_usage_by_stage
      
      # Recent API calls
      @recent_calls = @ekn.api_calls
                          .includes(:user, :session)
                          .order(created_at: :desc)
                          .limit(20)
      
      # Chart data
      @daily_costs = @ekn.api_calls
                         .where('created_at > ?', 30.days.ago)
                         .group("DATE(created_at)")
                         .sum(:total_cost)
                         .map { |date, cost| [date.to_s, cost.to_f.round(4)] }
      
      @daily_calls = @ekn.api_calls
                         .where('created_at > ?', 30.days.ago)
                         .group("DATE(created_at)")
                         .count
                         .map { |date, count| [date.to_s, count] }
    end
    
    private
    
    def set_ekn
      @ekn = Ekn.find(params[:id])
    end
    
    def calculate_success_rate(api_calls)
      return 0 if api_calls.count == 0
      (api_calls.successful.count.to_f / api_calls.count * 100).round(2)
    end
  end
end