# frozen_string_literal: true

# MCP Test Analyzer - Validates test execution results against expectations
#
# This service analyzes the results of a test case execution by:
# 1. Calculating execution metrics (response time, tool usage, etc.)
# 2. Validating results against test case expectations
# 3. Scoring response quality and correctness
# 4. Generating detailed assertion results
#
# Used by McpTestRunner to analyze each test case execution.
#
module Mcp
  class TestAnalyzer
    include Loggable
    
    attr_reader :test_case, :openai_response, :tool_calls, :expectations
    
    def initialize(test_case, openai_response, tool_calls)
      @test_case = test_case
      @openai_response = openai_response
      @tool_calls = tool_calls.to_a
      @expectations = test_case.effective_expectations
      
      log_debug "Initialized TestAnalyzer for case: #{test_case.name}"
      log_debug "Tool calls to analyze: #{@tool_calls.map(&:tool_name).join(', ')}"
    end
    
    # Calculate execution metrics
    def calculate_execution_metrics
      start_time = @tool_calls.map(&:created_at).min
      end_time = @tool_calls.map(&:completed_at).compact.max
      
      response_time_ms = if start_time && end_time
        ((end_time - start_time) * 1000).round
      else
        nil
      end
      
      metrics = {
        "response_time_ms" => response_time_ms,
        "tools_called_count" => @tool_calls.size,
        "tools_called" => @tool_calls.map(&:tool_name).uniq.sort,
        "successful_tools" => successful_tool_calls.size,
        "failed_tools" => failed_tool_calls.size,
        "total_duration_ms" => calculate_total_duration,
        "openai_tokens_used" => extract_token_usage,
        "ekn_targeted" => extract_targeted_ekn
      }
      
      log_debug "Calculated execution metrics: #{metrics.except('openai_tokens_used').inspect}"
      metrics
    end
    
    # Validate execution against test case expectations
    def validate_expectations
      assertions = {}
      
      # Validate tool usage
      assertions.merge!(validate_tool_expectations)
      
      # Validate EKN targeting
      assertions.merge!(validate_ekn_targeting)
      
      # Validate response timing
      assertions.merge!(validate_performance_expectations)
      
      # Validate result quality
      assertions.merge!(validate_quality_expectations)
      
      # Overall pass/fail status
      assertions["all_assertions_passed"] = assertions.values.all? { |v| v == true }
      
      log_info "Test case validation: #{assertions['all_assertions_passed'] ? 'PASSED' : 'FAILED'}"
      log_debug "Assertion details: #{assertions.inspect}"
      
      assertions
    end
    
    private
    
    def successful_tool_calls
      @successful_tool_calls ||= @tool_calls.select { |call| call.status == 'completed' }
    end
    
    def failed_tool_calls  
      @failed_tool_calls ||= @tool_calls.select { |call| call.status == 'failed' }
    end
    
    def calculate_total_duration
      return nil if @tool_calls.empty?
      
      earliest_start = @tool_calls.map(&:created_at).min
      latest_end = @tool_calls.map(&:completed_at).compact.max
      
      if earliest_start && latest_end
        ((latest_end - earliest_start) * 1000).round
      else
        nil
      end
    end
    
    def extract_token_usage
      # Extract token usage from OpenAI response if available
      @openai_response&.dig('usage', 'total_tokens') || 0
    end
    
    def extract_targeted_ekn
      # Extract EKN ID from the tool calls (should match expected EKN)
      ekn_ids = @tool_calls.map { |call| call.ekn&.id }.compact.uniq
      ekn_ids.first
    end
    
    def validate_tool_expectations
      expected_tools = expectations["tools_called"] || []
      actual_tools = @tool_calls.map(&:tool_name).uniq.sort
      
      assertions = {
        "expected_tools" => expected_tools,
        "actual_tools" => actual_tools,
        "correct_tools_called" => tools_match?(expected_tools, actual_tools),
        "unexpected_tools" => actual_tools - expected_tools,
        "missing_tools" => expected_tools - actual_tools
      }
      
      # Check minimum tool count
      if expectations["min_tools"]
        assertions["min_tools_met"] = actual_tools.size >= expectations["min_tools"]
      end
      
      # Check maximum tool count  
      if expectations["max_tools"]
        assertions["max_tools_respected"] = actual_tools.size <= expectations["max_tools"]
      end
      
      assertions
    end
    
    def validate_ekn_targeting
      expected_ekn_id = test_case.expected_ekn_id
      actual_ekn_id = extract_targeted_ekn
      
      assertions = {
        "expected_ekn_id" => expected_ekn_id,
        "actual_ekn_id" => actual_ekn_id,
        "correct_ekn_targeted" => expected_ekn_id.nil? || expected_ekn_id.to_s == actual_ekn_id.to_s
      }
      
      assertions
    end
    
    def validate_performance_expectations
      response_time_ms = calculate_execution_metrics["response_time_ms"]
      max_response_time = expectations["max_response_time_ms"] || 30000
      
      assertions = {
        "max_response_time_ms" => max_response_time,
        "actual_response_time_ms" => response_time_ms,
        "response_time_within_threshold" => response_time_ms.nil? || response_time_ms <= max_response_time
      }
      
      # Check success rate
      total_calls = @tool_calls.size
      successful_calls = successful_tool_calls.size
      
      if total_calls > 0
        success_rate = (successful_calls.to_f / total_calls * 100).round(1)
        min_success_rate = expectations["min_success_rate"] || 90.0
        
        assertions.merge!({
          "success_rate" => success_rate,
          "min_success_rate" => min_success_rate,
          "success_rate_met" => success_rate >= min_success_rate
        })
      end
      
      assertions
    end
    
    def validate_quality_expectations
      assertions = {}
      
      # Validate minimum results requirement
      if expectations["min_results"]
        result_count = extract_result_count
        assertions.merge!({
          "min_results_expected" => expectations["min_results"],
          "actual_results_count" => result_count,
          "min_results_met" => result_count >= expectations["min_results"]
        })
      end
      
      # Calculate quality score based on various factors
      quality_score = calculate_quality_score
      min_quality_score = expectations["min_quality_score"] || 0.7
      
      assertions.merge!({
        "response_quality_score" => quality_score,
        "min_quality_score" => min_quality_score,
        "quality_threshold_met" => quality_score >= min_quality_score
      })
      
      assertions
    end
    
    def tools_match?(expected, actual)
      return true if expected.empty? # No specific tools expected
      
      # Check if all expected tools were called
      (expected - actual).empty?
    end
    
    def extract_result_count
      # Extract result count from tool call responses
      total_results = 0
      
      @tool_calls.each do |call|
        next unless call.response_data.is_a?(Hash)
        
        # For search tool calls
        if call.tool_name == 'search' && call.response_data.dig('results')
          total_results += call.response_data['results'].size
        end
        
        # For other tools that return arrays
        %w[items entities bridges paths].each do |key|
          if call.response_data[key].is_a?(Array)
            total_results += call.response_data[key].size
          end
        end
      end
      
      total_results
    end
    
    def calculate_quality_score
      # Calculate quality score based on multiple factors
      factors = []
      
      # Factor 1: Tool execution success rate
      if @tool_calls.any?
        success_rate = successful_tool_calls.size.to_f / @tool_calls.size
        factors << success_rate
      end
      
      # Factor 2: Result relevance (simplified - based on non-empty results)
      non_empty_results = @tool_calls.count do |call|
        call.response_data.present? && has_meaningful_results?(call.response_data)
      end
      
      if @tool_calls.any?
        relevance_score = non_empty_results.to_f / @tool_calls.size
        factors << relevance_score
      end
      
      # Factor 3: Response completeness (did we get expected tools?)
      expected_tools = expectations["tools_called"] || []
      if expected_tools.any?
        actual_tools = @tool_calls.map(&:tool_name).uniq
        completeness_score = (expected_tools & actual_tools).size.to_f / expected_tools.size
        factors << completeness_score
      end
      
      # Return average of all factors, or 0.5 if no factors available
      factors.any? ? factors.sum / factors.size : 0.5
    end
    
    def has_meaningful_results?(response_data)
      return false unless response_data.is_a?(Hash)
      
      # Check for non-empty result arrays
      %w[results items entities bridges paths].any? do |key|
        response_data[key].is_a?(Array) && response_data[key].any?
      end
    end
  end
end