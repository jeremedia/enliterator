# frozen_string_literal: true

module Admin
  module ApiCallsHelper
    def sort_link(column, label)
      current_sort = params[:sort]
      current_direction = params[:direction] || 'desc'
      new_direction = (current_sort == column && current_direction == 'asc') ? 'desc' : 'asc'
      
      link_params = request.query_parameters.merge(sort: column, direction: new_direction)
      
      arrow = if current_sort == column
        current_direction == 'asc' ? '↑' : '↓'
      else
        ''
      end
      
      link_to "#{label} #{arrow}", admin_api_calls_path(link_params), class: "hover:text-blue-600"
    end
    
    def status_color_class(status)
      case status
      when 'success' then 'bg-green-100 text-green-800'
      when 'failed' then 'bg-red-100 text-red-800'
      when 'rate_limited' then 'bg-yellow-100 text-yellow-800'
      when 'timeout' then 'bg-orange-100 text-orange-800'
      when 'pending' then 'bg-blue-100 text-blue-800'
      else 'bg-gray-100 text-gray-800'
      end
    end
    
    def provider_color_class(provider)
      case provider
      when 'OpenaiApiCall' then 'bg-green-100 text-green-800'
      when 'AnthropicApiCall' then 'bg-purple-100 text-purple-800'
      when 'OllamaApiCall' then 'bg-gray-100 text-gray-800'
      else 'bg-blue-100 text-blue-800'
      end
    end
    
    def cost_color_class(cost)
      return 'text-gray-900' if cost.nil?
      if cost > 0.10
        'text-red-600 font-bold'
      elsif cost > 0.01
        'text-orange-600'
      else
        'text-gray-900'
      end
    end
    
    def response_time_color_class(time_ms)
      return 'text-gray-900' if time_ms.nil?
      if time_ms > 5000
        'text-red-600 font-bold'
      elsif time_ms > 2000
        'text-orange-600'
      else
        'text-gray-900'
      end
    end
  end
end