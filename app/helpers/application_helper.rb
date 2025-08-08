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
    when 'cancelled'
      'text-gray-600'
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
  
  def log_status_color_class(status)
    case status.to_s.downcase
    when 'debug'
      'text-gray-500'
    when 'info'
      'text-blue-600'
    when 'warn'
      'text-yellow-600'
    when 'error'
      'text-red-600'
    when 'fatal'
      'text-red-800 font-bold'
    else
      'text-gray-700'
    end
  end
  
  def log_item_color_class(status)
    log_status_color_class(status)
  end
  
  def log_label_icon(label)
    case label.to_s
    when 'pipeline'
      '🚀'
    when /stage_\d+/
      '📦'
    when 'errors'
      '❌'
    when 'warnings'
      '⚠️'
    when 'debug'
      '🔍'
    else
      '📝'
    end
  end
end