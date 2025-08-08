# frozen_string_literal: true

module Admin
  class ApiCallsController < Admin::BaseController
    before_action :set_api_call, only: [:show, :retry]
    
    def index
      @api_calls = filtered_api_calls
      
      # Calculate stats before sorting and pagination for accurate totals
      # Stats need clean scope without ordering
      @stats = calculate_stats(@api_calls)
      
      # Apply sorting after stats calculation
      @api_calls = apply_sorting(@api_calls)
      
      # Apply pagination after sorting
      @api_calls = @api_calls.page(params[:page]).per(params[:per_page] || 25)
      
      # Get unique values for filters
      @providers = ApiCall.distinct.pluck(:type).compact.sort
      @models = ApiCall.distinct.pluck(:model_used).compact.sort
      @services = ApiCall.distinct.pluck(:service_name).compact.sort
      @statuses = ApiCall.distinct.pluck(:status).compact.sort
      @ekns = Ekn.order(:name).pluck(:name, :id)  # For EKN filter dropdown
    end
    
    def show
      # Load related records if they exist
      @trackable = @api_call.trackable if @api_call.trackable_type.present?
      
      # Parse JSON fields for better display
      @request_params = @api_call.request_params
      @response_data = @api_call.response_data
      @error_details = @api_call.error_details
      @metadata = @api_call.metadata
      
      # Calculate some derived metrics
      @cost_per_token = @api_call.total_tokens.to_i > 0 ? 
        (@api_call.total_cost.to_f / @api_call.total_tokens * 1000).round(6) : 0
    end
    
    def retry
      # Create a new API call based on the failed one
      new_call = @api_call.dup
      new_call.status = 'pending'
      new_call.error_code = nil
      new_call.error_message = nil
      new_call.error_details = {}
      new_call.response_data = {}
      new_call.retry_count = (@api_call.retry_count || 0) + 1
      
      if new_call.save
        # Queue for retry (you'd implement the actual retry logic)
        ApiCallRetryJob.perform_later(new_call) if defined?(ApiCallRetryJob)
        redirect_to admin_api_call_path(new_call), 
                    notice: 'API call queued for retry'
      else
        redirect_back fallback_location: admin_api_calls_path,
                      alert: 'Failed to queue retry'
      end
    end
    
    def export
      @api_calls = filtered_api_calls
      
      respond_to do |format|
        format.csv { send_data generate_csv(@api_calls), filename: "api_calls_#{Date.current}.csv" }
        format.json { render json: @api_calls.limit(1000) }
      end
    end
    
    private
    
    def set_api_call
      @api_call = ApiCall.find(params[:id])
    end
    
    def filtered_api_calls
      scope = ApiCall.includes(:user, :trackable, :ekn, :session)
      
      # EKN filter - IMPORTANT for tracking per-EKN usage
      if params[:ekn_id].present?
        scope = scope.for_ekn(params[:ekn_id])
      end
      
      # Session filter
      if params[:session_id].present?
        scope = scope.for_session(params[:session_id])
      end
      
      # Show only calls without EKN
      if params[:without_ekn].present?
        scope = scope.without_ekn
      end
      
      # Date range filter
      if params[:date_from].present?
        scope = scope.where('created_at >= ?', params[:date_from])
      end
      
      if params[:date_to].present?
        scope = scope.where('created_at <= ?', params[:date_to])
      end
      
      # Provider filter
      if params[:provider].present?
        scope = scope.where(type: params[:provider])
      end
      
      # Model filter
      if params[:model].present?
        scope = scope.where(model_used: params[:model])
      end
      
      # Service filter
      if params[:service].present?
        scope = scope.where(service_name: params[:service])
      end
      
      # Status filter
      if params[:status].present?
        scope = scope.where(status: params[:status])
      end
      
      # Cost filter
      if params[:min_cost].present?
        scope = scope.where('total_cost >= ?', params[:min_cost])
      end
      
      if params[:max_cost].present?
        scope = scope.where('total_cost <= ?', params[:max_cost])
      end
      
      # Response time filter
      if params[:min_response_time].present?
        scope = scope.where('response_time_ms >= ?', params[:min_response_time])
      end
      
      if params[:max_response_time].present?
        scope = scope.where('response_time_ms <= ?', params[:max_response_time])
      end
      
      # Search query
      if params[:q].present?
        query = "%#{params[:q]}%"
        scope = scope.where(
          'service_name ILIKE ? OR endpoint ILIKE ? OR error_message ILIKE ? OR request_id ILIKE ?',
          query, query, query, query
        )
      end
      
      # Special filters
      case params[:special_filter]
      when 'expensive'
        scope = scope.where('total_cost > ?', 0.10)
      when 'slow'
        scope = scope.where('response_time_ms > ?', 5000)
      when 'failed'
        scope = scope.failed
      when 'cached'
        scope = scope.where(cached_response: true)
      when 'today'
        scope = scope.today
      when 'yesterday'
        scope = scope.yesterday
      when 'this_week'
        scope = scope.this_week
      when 'this_month'
        scope = scope.this_month
      end
      
      scope
    end
    
    def apply_sorting(scope)
      sort_column = params[:sort] || 'created_at'
      sort_direction = params[:direction] || 'desc'
      
      # Validate sort column to prevent SQL injection
      valid_columns = %w[created_at total_cost response_time_ms total_tokens 
                         model_used service_name status type endpoint]
      sort_column = 'created_at' unless valid_columns.include?(sort_column)
      sort_direction = 'desc' unless %w[asc desc].include?(sort_direction)
      
      scope.order("#{sort_column} #{sort_direction}")
    end
    
    def calculate_stats(scope)
      # Remove eager loading and ordering for aggregate queries to avoid SQL issues
      base_scope = scope.except(:includes, :preload, :eager_load, :order, :limit, :offset)
      
      {
        total_count: base_scope.count,
        total_cost: base_scope.sum(:total_cost).to_f.round(4),
        total_tokens: base_scope.sum(:total_tokens),
        avg_response_time: base_scope.average(:response_time_ms).to_f.round(2),
        success_rate: base_scope.count > 0 ? 
          (base_scope.successful.count.to_f / base_scope.count * 100).round(2) : 0,
        error_count: base_scope.failed.count,
        providers: base_scope.group(:type).count,
        models: base_scope.group(:model_used).count
      }
    end
    
    def generate_csv(api_calls)
      require 'csv'
      
      CSV.generate(headers: true) do |csv|
        csv << [
          'ID', 'Provider', 'Service', 'Endpoint', 'Model', 'Status',
          'Prompt Tokens', 'Completion Tokens', 'Total Tokens',
          'Input Cost', 'Output Cost', 'Total Cost',
          'Response Time (ms)', 'Error Code', 'Created At'
        ]
        
        api_calls.find_each do |call|
          csv << [
            call.id,
            call.type&.gsub('ApiCall', ''),
            call.service_name,
            call.endpoint,
            call.model_used,
            call.status,
            call.prompt_tokens,
            call.completion_tokens,
            call.total_tokens,
            call.input_cost,
            call.output_cost,
            call.total_cost,
            call.response_time_ms,
            call.error_code,
            call.created_at
          ]
        end
      end
    end
  end
end