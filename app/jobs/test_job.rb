# frozen_string_literal: true

# PURPOSE: Simple test job to verify Solid Queue is processing jobs correctly
# This job logs a message and demonstrates the job processing pipeline
class TestJob < ApplicationJob
  queue_as :default
  
  def perform(message = "Test job executed successfully!")
    Rails.logger.info "=" * 50
    Rails.logger.info "TestJob executing at #{Time.current}"
    Rails.logger.info "Message: #{message}"
    Rails.logger.info "=" * 50
    
    # Also output to console for visibility
    puts "=" * 50
    puts "TestJob executed: #{message}"
    puts "Time: #{Time.current}"
    puts "=" * 50
    
    # Return the message for testing
    message
  end
end