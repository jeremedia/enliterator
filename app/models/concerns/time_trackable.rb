# frozen_string_literal: true

# Concern for models that need temporal tracking
module TimeTrackable
  extend ActiveSupport::Concern
  
  included do
    # For entities that exist over a period
    scope :valid_at, ->(time) { 
      where("valid_time_start <= ? AND (valid_time_end IS NULL OR valid_time_end > ?)", time, time) 
    }
    
    scope :valid_between, ->(start_time, end_time) {
      where("valid_time_start <= ? AND (valid_time_end IS NULL OR valid_time_end > ?)", end_time, start_time)
    }
    
    scope :current, -> { valid_at(Time.current) }
    
    # For point-in-time observations
    scope :observed_between, ->(start_time, end_time) {
      where(observed_at: start_time..end_time)
    }
    
    scope :observed_before, ->(time) { where("observed_at < ?", time) }
    scope :observed_after, ->(time) { where("observed_at > ?", time) }
  end
  
  def valid_at?(time)
    return false unless valid_time_start
    
    valid_time_start <= time && (valid_time_end.nil? || valid_time_end > time)
  end
  
  def valid_during?(start_time, end_time)
    return false unless valid_time_start
    
    valid_time_start <= end_time && (valid_time_end.nil? || valid_time_end > start_time)
  end
  
  def temporal_bounds
    if respond_to?(:valid_time_start)
      {
        type: :period,
        start: valid_time_start,
        end: valid_time_end,
        duration: valid_time_end ? (valid_time_end - valid_time_start) : nil
      }
    elsif respond_to?(:observed_at)
      {
        type: :instant,
        at: observed_at
      }
    else
      nil
    end
  end
end