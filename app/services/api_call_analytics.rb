# frozen_string_literal: true

# Comprehensive analytics service for API call tracking
class ApiCallAnalytics
  class << self
    # Executive summary dashboard
    def dashboard(period = :today)
      {
        summary: summary_stats(period),
        providers: provider_comparison(period),
        costs: cost_analysis(period),
        performance: performance_metrics(period),
        errors: error_analysis(period),
        trends: trend_analysis(period),
        alerts: active_alerts(period),
        recommendations: generate_recommendations(period)
      }
    end
    
    # High-level summary statistics
    def summary_stats(period = :today)
      scope = period_scope(period)
      
      {
        total_calls: scope.count,
        successful_calls: scope.successful.count,
        failed_calls: scope.failed.count,
        success_rate: calculate_success_rate(scope),
        total_cost: scope.sum(:total_cost).to_f.round(4),
        total_tokens: scope.sum(:total_tokens),
        unique_models: scope.distinct.count(:model_used),
        unique_services: scope.distinct.count(:service_name),
        period: period
      }
    end
    
    # Provider comparison
    def provider_comparison(period = :month)
      scope = period_scope(period)
      
      providers = %w[OpenaiApiCall AnthropicApiCall OllamaApiCall]
      
      providers.map do |provider_class|
        provider_scope = scope.where(type: provider_class)
        next if provider_scope.count == 0
        
        {
          provider: provider_class.gsub('ApiCall', ''),
          calls: provider_scope.count,
          cost: provider_scope.sum(:total_cost).to_f.round(4),
          tokens: provider_scope.sum(:total_tokens),
          avg_response_time: provider_scope.average(:response_time_ms).to_f.round(2),
          success_rate: calculate_success_rate(provider_scope),
          models_used: provider_scope.distinct.pluck(:model_used),
          top_services: provider_scope
            .group(:service_name)
            .count
            .sort_by { |_, v| -v }
            .first(5)
        }
      end.compact
    end
    
    # Detailed cost analysis
    def cost_analysis(period = :month)
      scope = period_scope(period)
      
      {
        total_cost: scope.sum(:total_cost).to_f.round(4),
        by_provider: scope.group(:type).sum(:total_cost).transform_keys { |k| k.gsub('ApiCall', '') },
        by_model: scope
          .group(:model_used)
          .sum(:total_cost)
          .sort_by { |_, v| -v }
          .first(10)
          .to_h,
        by_service: scope
          .group(:service_name)
          .sum(:total_cost)
          .sort_by { |_, v| -v }
          .first(10)
          .to_h,
        by_day: scope
          .group("DATE(created_at)")
          .sum(:total_cost)
          .transform_values { |v| v.to_f.round(4) },
        expensive_calls: scope
          .where('total_cost > ?', 0.10)
          .order(total_cost: :desc)
          .limit(10)
          .map { |call| call_summary(call) },
        cost_per_token: {
          avg: calculate_cost_per_token(scope),
          by_model: scope
            .group(:model_used)
            .pluck(Arel.sql('model_used, SUM(total_cost)::float / NULLIF(SUM(total_tokens), 0) * 1000'))
            .to_h
        },
        forecast: cost_forecast(period)
      }
    end
    
    # Performance metrics
    def performance_metrics(period = :today)
      scope = period_scope(period)
      
      {
        avg_response_time: scope.average(:response_time_ms).to_f.round(2),
        median_response_time: percentile(scope, :response_time_ms, 0.5),
        p95_response_time: percentile(scope, :response_time_ms, 0.95),
        p99_response_time: percentile(scope, :response_time_ms, 0.99),
        by_provider: scope
          .group(:type)
          .average(:response_time_ms)
          .transform_keys { |k| k.gsub('ApiCall', '') }
          .transform_values { |v| v.to_f.round(2) },
        by_model: scope
          .group(:model_used)
          .average(:response_time_ms)
          .transform_values { |v| v.to_f.round(2) },
        slowest_calls: scope
          .order(response_time_ms: :desc)
          .limit(10)
          .map { |call| call_summary(call) },
        retry_rate: calculate_retry_rate(scope),
        cache_hit_rate: calculate_cache_hit_rate(scope),
        tokens_per_second: calculate_throughput(scope)
      }
    end
    
    # Error analysis
    def error_analysis(period = :today)
      scope = period_scope(period).failed
      
      {
        total_errors: scope.count,
        error_rate: (scope.count.to_f / period_scope(period).count * 100).round(2),
        by_type: scope.group(:status).count,
        by_error_code: scope
          .group(:error_code)
          .count
          .sort_by { |_, v| -v }
          .first(10)
          .to_h,
        by_service: scope
          .group(:service_name)
          .count
          .sort_by { |_, v| -v }
          .first(10)
          .to_h,
        by_model: scope.group(:model_used).count,
        recent_errors: scope
          .order(created_at: :desc)
          .limit(10)
          .map { |call| error_summary(call) },
        rate_limits: scope.where(status: 'rate_limited').count,
        timeouts: scope.where(status: 'timeout').count
      }
    end
    
    # Trend analysis
    def trend_analysis(period = :week)
      current_scope = period_scope(period)
      previous_scope = previous_period_scope(period)
      
      {
        calls: {
          current: current_scope.count,
          previous: previous_scope.count,
          change: percentage_change(previous_scope.count, current_scope.count)
        },
        cost: {
          current: current_scope.sum(:total_cost).to_f.round(4),
          previous: previous_scope.sum(:total_cost).to_f.round(4),
          change: percentage_change(
            previous_scope.sum(:total_cost),
            current_scope.sum(:total_cost)
          )
        },
        tokens: {
          current: current_scope.sum(:total_tokens),
          previous: previous_scope.sum(:total_tokens),
          change: percentage_change(
            previous_scope.sum(:total_tokens),
            current_scope.sum(:total_tokens)
          )
        },
        error_rate: {
          current: calculate_error_rate(current_scope),
          previous: calculate_error_rate(previous_scope),
          change: percentage_point_change(
            calculate_error_rate(previous_scope),
            calculate_error_rate(current_scope)
          )
        },
        avg_response_time: {
          current: current_scope.average(:response_time_ms).to_f.round(2),
          previous: previous_scope.average(:response_time_ms).to_f.round(2),
          change: percentage_change(
            previous_scope.average(:response_time_ms),
            current_scope.average(:response_time_ms)
          )
        }
      }
    end
    
    # Model usage analysis
    def model_usage(period = :month)
      scope = period_scope(period)
      
      models = scope.distinct.pluck(:model_used).compact
      
      models.map do |model|
        model_scope = scope.where(model_used: model)
        
        {
          model: model,
          provider: detect_provider(model),
          calls: model_scope.count,
          cost: model_scope.sum(:total_cost).to_f.round(4),
          tokens: model_scope.sum(:total_tokens),
          avg_response_time: model_scope.average(:response_time_ms).to_f.round(2),
          success_rate: calculate_success_rate(model_scope),
          cost_per_1k_tokens: calculate_cost_per_token(model_scope),
          top_services: model_scope
            .group(:service_name)
            .count
            .sort_by { |_, v| -v }
            .first(5)
        }
      end.sort_by { |m| -m[:cost] }
    end
    
    # Service usage analysis
    def service_usage(period = :month)
      scope = period_scope(period)
      
      services = scope.distinct.pluck(:service_name).compact
      
      services.map do |service|
        service_scope = scope.where(service_name: service)
        
        {
          service: service,
          calls: service_scope.count,
          cost: service_scope.sum(:total_cost).to_f.round(4),
          tokens: service_scope.sum(:total_tokens),
          avg_response_time: service_scope.average(:response_time_ms).to_f.round(2),
          success_rate: calculate_success_rate(service_scope),
          models_used: service_scope.distinct.pluck(:model_used),
          error_rate: calculate_error_rate(service_scope),
          top_errors: service_scope
            .failed
            .group(:error_code)
            .count
            .first(3)
        }
      end.sort_by { |s| -s[:calls] }
    end
    
    # Cost forecast
    def cost_forecast(period = :month, days_ahead = 30)
      scope = period_scope(period)
      
      days_in_period = case period
                      when :today then 1
                      when :week then 7
                      when :month then 30
                      else 30
                      end
      
      daily_avg = scope.sum(:total_cost).to_f / days_in_period
      
      {
        daily_average: daily_avg.round(4),
        projected_monthly: (daily_avg * 30).round(2),
        projected_cost: (daily_avg * days_ahead).round(2),
        days_ahead: days_ahead,
        based_on: period
      }
    end
    
    # Active alerts
    def active_alerts(period = :today)
      scope = period_scope(period)
      alerts = []
      
      # High cost alert
      if scope.sum(:total_cost) > 100
        alerts << {
          type: 'high_cost',
          severity: 'warning',
          message: "Daily API costs exceed $100",
          value: scope.sum(:total_cost).to_f.round(2)
        }
      end
      
      # High error rate
      error_rate = calculate_error_rate(scope)
      if error_rate > 10
        alerts << {
          type: 'high_error_rate',
          severity: 'critical',
          message: "Error rate above 10%",
          value: "#{error_rate.round(2)}%"
        }
      end
      
      # Rate limiting
      rate_limited = scope.where(status: 'rate_limited').count
      if rate_limited > 10
        alerts << {
          type: 'rate_limiting',
          severity: 'warning',
          message: "Multiple rate limit errors",
          value: rate_limited
        }
      end
      
      # Slow responses
      slow_calls = scope.where('response_time_ms > ?', 5000).count
      if slow_calls > 10
        alerts << {
          type: 'slow_responses',
          severity: 'info',
          message: "Multiple slow API calls (>5s)",
          value: slow_calls
        }
      end
      
      alerts
    end
    
    # Generate recommendations
    def generate_recommendations(period = :week)
      scope = period_scope(period)
      recommendations = []
      
      # Model optimization
      expensive_models = scope
        .group(:model_used)
        .average('total_cost::float / NULLIF(total_tokens, 0) * 1000')
        .transform_values { |v| v || 0 }
        .sort_by { |_, v| -v }
        .first(3)
      
      if expensive_models.any? { |_, cost| cost > 0.01 }
        recommendations << {
          type: 'model_optimization',
          message: "Consider using more cost-effective models",
          details: "Models with high cost per token: #{expensive_models.map(&:first).join(', ')}"
        }
      end
      
      # Caching opportunity
      duplicate_requests = scope
        .group(:service_name, :endpoint, :request_params)
        .having('COUNT(*) > 5')
        .count
      
      if duplicate_requests.any?
        recommendations << {
          type: 'caching',
          message: "Implement caching for frequently repeated requests",
          details: "#{duplicate_requests.size} request patterns repeated >5 times"
        }
      end
      
      # Error reduction
      error_rate = calculate_error_rate(scope)
      if error_rate > 5
        top_errors = scope.failed.group(:error_code).count.first(3)
        recommendations << {
          type: 'error_reduction',
          message: "Address common errors to improve reliability",
          details: "Top errors: #{top_errors.map { |k, v| "#{k} (#{v})" }.join(', ')}"
        }
      end
      
      # Performance optimization
      slow_services = scope
        .group(:service_name)
        .average(:response_time_ms)
        .select { |_, avg| avg > 3000 }
      
      if slow_services.any?
        recommendations << {
          type: 'performance',
          message: "Optimize slow services",
          details: "Services averaging >3s: #{slow_services.keys.join(', ')}"
        }
      end
      
      recommendations
    end
    
    private
    
    def period_scope(period)
      case period
      when :today then ApiCall.today
      when :yesterday then ApiCall.yesterday
      when :week then ApiCall.this_week
      when :month then ApiCall.this_month
      when Range then ApiCall.where(created_at: period)
      else ApiCall.where(created_at: period)
      end
    end
    
    def previous_period_scope(period)
      case period
      when :today then ApiCall.yesterday
      when :yesterday then ApiCall.where(created_at: 2.days.ago.all_day)
      when :week then ApiCall.where(created_at: 2.weeks.ago..1.week.ago)
      when :month then ApiCall.where(created_at: 2.months.ago..1.month.ago)
      else ApiCall.none
      end
    end
    
    def calculate_success_rate(scope)
      return 0 if scope.count == 0
      (scope.successful.count.to_f / scope.count * 100).round(2)
    end
    
    def calculate_error_rate(scope)
      return 0 if scope.count == 0
      (scope.failed.count.to_f / scope.count * 100).round(2)
    end
    
    def calculate_retry_rate(scope)
      return 0 if scope.count == 0
      (scope.where('retry_count > 0').count.to_f / scope.count * 100).round(2)
    end
    
    def calculate_cache_hit_rate(scope)
      return 0 if scope.count == 0
      (scope.where(cached_response: true).count.to_f / scope.count * 100).round(2)
    end
    
    def calculate_cost_per_token(scope)
      total_cost = scope.sum(:total_cost)
      total_tokens = scope.sum(:total_tokens)
      return 0 if total_tokens == 0
      
      (total_cost.to_f / total_tokens * 1000).round(6)
    end
    
    def calculate_throughput(scope)
      total_tokens = scope.sum(:total_tokens)
      total_time = scope.sum(:response_time_ms)
      return 0 if total_time == 0
      
      (total_tokens.to_f / total_time * 1000).round(2)  # tokens per second
    end
    
    def percentile(scope, column, percentile_value)
      values = scope.pluck(column).compact.sort
      return nil if values.empty?
      
      index = (percentile_value * (values.length - 1)).round
      values[index]
    end
    
    def percentage_change(old_value, new_value)
      return 0 if old_value.nil? || old_value == 0
      return 0 if new_value.nil?
      ((new_value - old_value).to_f / old_value * 100).round(2)
    end
    
    def percentage_point_change(old_value, new_value)
      (new_value - old_value).round(2)
    end
    
    def detect_provider(model)
      case model
      when /gpt|dall-e|whisper|embedding/ then 'OpenAI'
      when /claude/ then 'Anthropic'
      when /llama|mistral|mixtral|phi|gemma|qwen|codellama/ then 'Ollama'
      else 'Unknown'
      end
    end
    
    def call_summary(call)
      {
        id: call.id,
        service: call.service_name,
        model: call.model_used,
        cost: call.total_cost.to_f.round(4),
        tokens: call.total_tokens,
        response_time: call.response_time_ms,
        created_at: call.created_at
      }
    end
    
    def error_summary(call)
      {
        id: call.id,
        service: call.service_name,
        model: call.model_used,
        error_code: call.error_code,
        error_message: call.error_message&.truncate(100),
        created_at: call.created_at
      }
    end
  end
end