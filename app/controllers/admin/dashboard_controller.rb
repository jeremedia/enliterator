# frozen_string_literal: true

module Admin
  class DashboardController < BaseController
    def index
      @settings_count = OpenaiSetting.count
      @active_settings = OpenaiSetting.active.count
      @prompt_templates_count = PromptTemplate.count
      @active_templates = PromptTemplate.active.count
      @fine_tune_jobs = FineTuneJob.order(created_at: :desc).limit(5)
      @current_model = FineTuneJob.current_model
      
      # Calculate usage stats (placeholder for now)
      @usage_stats = calculate_usage_stats
    end
    
    private
    
    def calculate_usage_stats
      today_calls = ApiCall.today
      month_calls = ApiCall.this_month
      
      # Calculate batch savings (estimate based on typical 50% savings)
      batch_cost = today_calls.where("endpoint LIKE ?", '%batch%').sum(:total_cost).to_f
      estimated_non_batch_cost = batch_cost * 2 # Batch API typically saves 50%
      
      {
        today_cost: today_calls.sum(:total_cost).to_f,
        month_cost: month_calls.sum(:total_cost).to_f,
        batch_savings: estimated_non_batch_cost - batch_cost,
        total_requests: month_calls.count,
        extraction_requests: month_calls.where("service_name LIKE ?", '%Extraction%').count,
        routing_requests: month_calls.where("service_name LIKE ?", '%Routing%').count,
        # Additional useful stats
        today_requests: today_calls.count,
        failed_requests: today_calls.failed.count,
        avg_response_time: today_calls.average(:response_time_ms).to_f.round(2)
      }
    rescue => e
      Rails.logger.error "Error calculating usage stats: #{e.message}"
      # Return defaults if there's an error
      {
        today_cost: 0.0,
        month_cost: 0.0,
        batch_savings: 0.0,
        total_requests: 0,
        extraction_requests: 0,
        routing_requests: 0,
        today_requests: 0,
        failed_requests: 0,
        avg_response_time: 0.0
      }
    end
  end
end