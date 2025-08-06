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
      {
        today_cost: 0.0,
        month_cost: 0.0,
        batch_savings: 0.0,
        total_requests: 0,
        extraction_requests: 0,
        routing_requests: 0
      }
    end
  end
end