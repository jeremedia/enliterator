# frozen_string_literal: true

# app/models/concerns/loggable.rb
module Loggable
  extend ActiveSupport::Concern

  included do
    has_many :logs, as: :loggable, dependent: :destroy
    alias_method :l, :log
  end

  DEFAULT_STATE = "info"
  
  LOG_LEVELS = {
    debug: "debug",
    info: "info",
    warn: "warn",
    error: "error",
    fatal: "fatal"
  }.freeze


  def self.thread_run_logs
    # logs with 'thread.run' in text
    LogItem.where("text LIKE '%thread.run.complete%'")
    # FaradayOpenAiLogItem.where("request->>'url' LIKE '%/runs'").last

  end
  def log(text, label: "log", state: DEFAULT_STATE)
    self.add_log_entry(text, label, state)
  end
  
  def log_debug(text, label: "log")
    log(text, label: label, state: LOG_LEVELS[:debug])
  end
  
  def log_info(text, label: "log")
    log(text, label: label, state: LOG_LEVELS[:info])
  end
  
  def log_warn(text, label: "log")
    log(text, label: label, state: LOG_LEVELS[:warn])
  end
  
  def log_error(text, label: "log")
    log(text, label: label, state: LOG_LEVELS[:error])
  end
  
  def log_fatal(text, label: "log")
    log(text, label: label, state: LOG_LEVELS[:fatal])
  end

  # Define methods to create or access logs with specific labels
  def find_or_create_log(label = "log")
    Rails.logger.silence do
    logs.find_or_create_by(label: label)
    end
  end

  def add_log_entry(log_text, log_label = "log", status = "")
    log = find_or_create_log(log_label)
    log_entry = log.log_items.create(text: log_text, status: status)
    ap "<-LOG #{log_entry.id}-> #{log_text}"
    
    # Broadcast progress updates for SchemaRequest logs to SlackChannel UI
    if defined?(SchemaRequest) && self.is_a?(SchemaRequest) && should_broadcast_log_message?(log_text)
      broadcast_progress_update(format_log_message_for_ui(log_text))
    end
  end

  # Additional methods for log entries
  def log_entries(label)
    find_or_create_log(label).log_items
  end

  # Check if log message should be broadcast to UI
  def should_broadcast_log_message?(log_text)
    return false unless respond_to?(:broadcast_progress_update)
    
    # Broadcast these types of messages
    broadcast_patterns = [
      /executing.*tool/i,
      /tool.*execution/i,
      /begin.*api.*call/i,
      /end.*api.*call/i,
      /deep analysis/i,
      /analysis.*progress/i,
      /generating.*response/i,
      /comprehensive.*report/i,
      /continuation.*api.*call/i,
      /tool.*continuation/i,
      /parsing.*response/i,
      /successfully.*parsed/i
    ]
    
    broadcast_patterns.any? { |pattern| log_text.match?(pattern) }
  end
  
  # Format log message for user-friendly UI display
  def format_log_message_for_ui(log_text)
    case log_text
    when /executing.*tool.*(\w+)/i
      "🔧 Executing tool: #{$1}"
    when /tool.*execution.*complete/i
      "✅ Tool execution complete"
    when /begin.*api.*call/i
      "🌐 Starting API call..."
    when /end.*api.*call/i
      "📡 API call complete"
    when /deep analysis.*progress/i
      "🧠 Deep analysis in progress..."
    when /comprehensive.*report/i
      "📊 Generating comprehensive report..."
    when /continuation.*api.*call/i
      "🔄 Processing tool results..."
    when /successfully.*parsed/i
      "✨ Response parsed successfully"
    when /generating.*response/i
      "⚡ Generating response..."
    else
      # Clean up technical parts and show simplified version
      cleaned = log_text.gsub(/\d{4}-\d{2}-\d{2}.*?\d{2}:\d{2}:\d{2}/, '') # Remove timestamps
                        .gsub(/\[\w+\]/, '') # Remove log levels
                        .strip
      "⚙️ #{cleaned}"
    end
  end

  def print_log
    return "no logs" if logs.empty?
    first_log_time = logs.first.created_at
    logs.each do |log|
      prev_elapsed = 0
      # puts "Log: #{log.label}"
      log.log_items.each_with_index do |item, index|
        seconds_passed = item.created_at - first_log_time
        elapsed = (seconds_passed - prev_elapsed).round(3)
        prev_elapsed = seconds_passed
        elapsed_padded = elapsed.to_s.ljust(5, "0")
        padded_index = index.to_s.rjust(3, "0")
        padded_seconds = seconds_passed.to_s.ljust(9, "0")
        puts "#{padded_index} - #{padded_seconds} - #{elapsed_padded} - #{item.text}"
      end
    end
    self
  end
end