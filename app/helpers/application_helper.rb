module ApplicationHelper
  def status_color_class(status)
    case status.to_s
    when 'completed'
      'text-green-600'
    when 'running', 'retrying'
      'text-blue-600'
    when 'failed'
      'text-red-600'
    when 'paused'
      'text-yellow-600'
    when 'initialized'
      'text-gray-600'
    else
      'text-gray-500'
    end
  end
  
  def stage_status_class(status)
    case status.to_s
    when 'completed'
      'bg-green-50 border-green-200'
    when 'running'
      'bg-blue-50 border-blue-200 animate-pulse'
    when 'failed'
      'bg-red-50 border-red-200'
    else
      'bg-gray-50 border-gray-200'
    end
  end
end