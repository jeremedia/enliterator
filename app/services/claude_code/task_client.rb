# frozen_string_literal: true

# Claude Code Task Client - Bridge between Rails and Claude Code
#
# This service provides the missing bridge to invoke Claude Code as an intelligent
# evaluation agent from within the Rails application. It replaces the conceptual
# Task.call() with actual API integration.
#
module ClaudeCode
  class TaskClient
    include HTTParty
    
    # Claude Code API endpoint (would need to be configured)
    base_uri ENV.fetch('CLAUDE_CODE_API_URL', 'https://api.anthropic.com/v1/claude-code')
    
    def self.call(subagent_type:, description:, prompt:, timeout: 120)
      new.call(
        subagent_type: subagent_type,
        description: description, 
        prompt: prompt,
        timeout: timeout
      )
    end
    
    def initialize
      @api_key = ENV['CLAUDE_CODE_API_KEY'] || ENV['ANTHROPIC_API_KEY']
      @client_id = ENV['CLAUDE_CODE_CLIENT_ID'] || 'enliterator-mcp-testing'
      
      raise "Claude Code API key not configured" unless @api_key
    end
    
    def call(subagent_type:, description:, prompt:, timeout: 120)
      Rails.logger.info "Invoking Claude Code agent: #{description}"
      
      request_payload = {
        agent_type: subagent_type,
        task_description: description,
        prompt: prompt,
        timeout: timeout,
        client_context: {
          application: 'enliterator',
          component: 'mcp_testing',
          timestamp: Time.current.iso8601
        }
      }
      
      begin
        response = self.class.post(
          '/tasks',
          headers: {
            'Authorization' => "Bearer #{@api_key}",
            'Content-Type' => 'application/json',
            'X-Client-ID' => @client_id
          },
          body: request_payload.to_json,
          timeout: timeout + 10  # Add buffer for API overhead
        )
        
        handle_response(response)
        
      rescue Net::TimeoutError => e
        Rails.logger.error "Claude Code API timeout: #{e.message}"
        raise TaskTimeoutError, "Claude Code evaluation timed out after #{timeout}s"
        
      rescue => e
        Rails.logger.error "Claude Code API error: #{e.message}"
        raise TaskExecutionError, "Failed to invoke Claude Code agent: #{e.message}"
      end
    end
    
    private
    
    def handle_response(response)
      case response.code
      when 200
        result = response.parsed_response
        Rails.logger.info "Claude Code agent completed successfully"
        
        # Return the agent's response content
        result['agent_response'] || result['content'] || result.to_s
        
      when 400
        error_msg = response.parsed_response['error'] || 'Bad request'
        raise TaskExecutionError, "Claude Code API error: #{error_msg}"
        
      when 401
        raise TaskAuthenticationError, "Invalid Claude Code API credentials"
        
      when 429
        raise TaskRateLimitError, "Claude Code API rate limit exceeded"
        
      when 500..599
        error_msg = response.parsed_response['error'] || 'Server error'
        raise TaskExecutionError, "Claude Code API server error: #{error_msg}"
        
      else
        raise TaskExecutionError, "Unexpected Claude Code API response: #{response.code}"
      end
    end
  end
  
  # Custom exception classes for different error types
  class TaskError < StandardError; end
  class TaskTimeoutError < TaskError; end
  class TaskExecutionError < TaskError; end
  class TaskAuthenticationError < TaskError; end
  class TaskRateLimitError < TaskError; end
end