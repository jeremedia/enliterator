# frozen_string_literal: true

# Base service class for all service objects in the application
# Provides a consistent interface and common functionality
class ApplicationService
  class ServiceError < StandardError; end
  
  def self.call(...)
    new(...).call
  end
  
  private
  
  def with_transaction(&block)
    ApplicationRecord.transaction(&block)
  end
  
  def with_neo4j_transaction(&block)
    Graph::Connection.instance.transaction(&block)
  end
  
  def log_info(message, **context)
    Rails.logger.info({ message: message, service: self.class.name, **context }.to_json)
  end
  
  def log_error(message, error: nil, **context)
    Rails.logger.error({ 
      message: message, 
      service: self.class.name,
      error: error&.message,
      backtrace: error&.backtrace&.first(5),
      **context 
    }.to_json)
  end
  
  def measure_time(operation_name)
    start_time = Time.current
    result = yield
    duration = Time.current - start_time
    
    log_info("Operation completed", 
      operation: operation_name, 
      duration_ms: (duration * 1000).round
    )
    
    result
  end
  
  def with_retry(max_attempts: 3, backoff: :exponential)
    attempt = 0
    
    begin
      attempt += 1
      yield
    rescue StandardError => e
      if attempt < max_attempts
        sleep_time = backoff == :exponential ? (2 ** (attempt - 1)) : 1
        sleep(sleep_time)
        retry
      else
        raise
      end
    end
  end
end