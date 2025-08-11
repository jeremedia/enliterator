# frozen_string_literal: true

# MCP Test Runner - Orchestrates complete test suite execution
#
# This service manages the full lifecycle of MCP test suite execution:
# 1. Creates test run and executions
# 2. Calls OpenAI saved prompts with variable substitution
# 3. Correlates responses to MCP tool calls
# 4. Analyzes results against expectations
# 5. Updates metrics and completion status
#
# Usage:
#   runner = Mcp::TestRunner.new(test_suite)
#   test_run = runner.execute_suite
#   # Returns completed McpTestRun with all execution results
#
module Mcp
  class TestRunner
    # Use Rails logger instead of Loggable concern (which expects ActiveRecord model)
    # include Loggable
    
    attr_reader :test_suite, :test_run, :config
    
    def initialize(test_suite)
      @test_suite = test_suite
      @config = test_suite.effective_test_config
      @openai_client = OPENAI  # Use global OpenAI client instance
      Rails.logger.info "Initialized MCP TestRunner for suite: #{test_suite.name}"
    end
    
    # Execute the complete test suite
    def execute_suite
      validate_prerequisites!
      
      @test_run = create_test_run
      @test_run.start!
      
      Rails.logger.info "Starting test suite execution: #{test_suite.name} (Run ##{@test_run.id})"
      
      begin
        execute_test_cases
        analyze_results
        @test_run.complete!
        Rails.logger.info "Test suite completed successfully: #{@test_run.success_rate}% success rate"
      rescue => e
        Rails.logger.error "Test suite execution failed: #{e.message}"
        @test_run.fail!(e.message)
        raise
      end
      
      @test_run
    end
    
    # Execute a single test case (can be used independently)
    def execute_test_case(test_case, test_run = nil)
      test_run ||= @test_run || create_test_run
      
      execution = create_test_execution(test_run, test_case)
      execution.start!
      
      Rails.logger.info "Executing test case: #{test_case.name}"
      
      begin
        # Generate unique request ID for correlation
        request_id = generate_request_id(test_case)
        
        # Call OpenAI saved prompt with merged variables
        response = call_openai_saved_prompt(test_case, request_id)
        
        # Wait for and collect MCP tool calls
        tool_calls = collect_tool_calls(request_id, config['timeout'] || 30)
        
        # Analyze execution results
        metrics, assertions = analyze_execution(test_case, response, tool_calls)
        
        # Complete the execution
        execution.complete!(metrics, assertions)
        
        Rails.logger.info "Test case completed: #{test_case.name} - #{assertions['all_assertions_passed'] ? 'PASSED' : 'FAILED'}"
        
      rescue => e
        Rails.logger.error "Test case execution failed: #{test_case.name} - #{e.message}"
        execution.fail!(e.message, { "error_type" => e.class.name })
        raise if config['fail_fast']
      end
      
      execution
    end
    
    private
    
    def validate_prerequisites!
      raise "Test suite must be ready to run" unless test_suite.ready_to_run?
      raise "OpenAI API key not configured" unless ENV['OPENAI_API_KEY'].present?
      raise "No enabled test cases found" if test_suite.enabled_test_cases_count.zero?
    end
    
    def create_test_run
      McpTestRun.create!(
        mcp_test_suite: test_suite,
        status: :pending,
        summary_metrics: {
          "suite_name" => test_suite.name,
          "total_cases_planned" => test_suite.enabled_test_cases_count,
          "config" => config
        }
      )
    end
    
    def create_test_execution(test_run, test_case)
      McpTestExecution.create!(
        mcp_test_run: test_run,
        mcp_test_case: test_case,
        status: :pending
      )
    end
    
    def execute_test_cases
      enabled_cases = test_suite.mcp_test_cases.enabled
      
      Rails.logger.info "Executing #{enabled_cases.count} test cases"
      
      if config['concurrent_executions'] && config['concurrent_executions'] > 1
        execute_test_cases_concurrently(enabled_cases)
      else
        execute_test_cases_sequentially(enabled_cases)
      end
    end
    
    def execute_test_cases_sequentially(test_cases)
      test_cases.each do |test_case|
        execute_test_case(test_case, @test_run)
      end
    end
    
    def execute_test_cases_concurrently(test_cases)
      # For now, implement sequential execution
      # TODO: Add proper concurrent execution with thread pool
      Rails.logger.info "Concurrent execution requested but not yet implemented, falling back to sequential"
      execute_test_cases_sequentially(test_cases)
    end
    
    def generate_request_id(test_case)
      "mcp_test_#{@test_run.id}_#{test_case.id}_#{Time.now.to_i}_#{SecureRandom.hex(4)}"
    end
    
    def call_openai_saved_prompt(test_case, request_id)
      # Merge base variables with test case overrides
      variables = test_suite.merged_variables(test_case.variable_overrides)
      
      Rails.logger.debug "Calling OpenAI saved prompt #{test_suite.saved_prompt_id} with variables: #{variables.keys.join(', ')}"
      
      # Use OpenAI Saved Prompts API (not chat completions)
      response = @openai_client.post(
        path: "prompts/#{test_suite.saved_prompt_id}/run",
        parameters: {
          variables: variables,
          metadata: {
            test_execution_context: {
              request_id: request_id,
              test_run_id: @test_run.id,
              test_case_id: test_case.id,
              ekn_id: variables['EKN_ID']
            }
          }
        }
      )
      
      Rails.logger.debug "OpenAI response received for request #{request_id}"
      response
      
    rescue => e
      Rails.logger.error "OpenAI saved prompt call failed: #{e.message}"
      raise "Failed to call OpenAI saved prompt: #{e.message}"
    end
    
    def collect_tool_calls(request_id, timeout_seconds)
      Rails.logger.debug "Collecting MCP tool calls for request ID: #{request_id}"
      
      start_time = Time.current
      collected_calls = []
      
      # Poll for tool calls with the matching request ID
      loop do
        # Look for tool calls with matching OpenAI request ID
        new_calls = McpToolCall.by_openai_request(request_id)
                              .where(created_at: start_time..)
        
        new_calls.each do |call|
          unless collected_calls.include?(call.id)
            collected_calls << call.id
            Rails.logger.debug "Found tool call: #{call.tool_name} (#{call.id})"
          end
        end
        
        # Check if we've exceeded timeout
        if Time.current - start_time > timeout_seconds
          Rails.logger.warn "Timeout waiting for tool calls after #{timeout_seconds}s"
          break
        end
        
        # Check if we have any tool calls and they're all completed
        if collected_calls.any?
          calls = McpToolCall.where(id: collected_calls)
          if calls.all? { |c| ['completed', 'failed', 'timeout'].include?(c.status) }
            Rails.logger.debug "All tool calls completed"
            break
          end
        end
        
        sleep 0.5 # Poll every 500ms
      end
      
      McpToolCall.where(id: collected_calls)
    end
    
    def analyze_execution(test_case, openai_response, tool_calls)
      # Use intelligent evaluation instead of basic TestAnalyzer
      evaluator = Mcp::IntelligentEvaluator.new(test_case, openai_response, tool_calls, @test_run)
      
      # Get comprehensive intelligent assessment
      metrics, assertions = evaluator.evaluate
      
      # Create meta-creation assessment if this is evaluating EKN personality
      if test_case.expected_ekn_id && assertions['personality_authenticity_passed'] != nil
        create_meta_creation_assessment(test_case, metrics, assertions)
      end
      
      [metrics, assertions]
    end
    
    def analyze_results
      executions = @test_run.mcp_test_executions.includes(:mcp_test_case)
      
      total_cases = executions.count
      passed_cases = executions.select(&:all_assertions_passed?).count
      failed_cases = executions.where(status: 'failed').count
      
      avg_response_time = calculate_average_response_time(executions)
      total_tool_calls = executions.sum { |e| e.execution_metrics&.dig('tools_called_count') || 0 }
      
      Rails.logger.info "Test run analysis: #{passed_cases}/#{total_cases} passed, avg response time: #{avg_response_time}ms"
    end
    
    def calculate_average_response_time(executions)
      completed_executions = executions.select { |e| e.response_time_ms }
      return 0 if completed_executions.empty?
      
      total_time = completed_executions.sum(&:response_time_ms)
      (total_time.to_f / completed_executions.size).round
    end
    
    def create_meta_creation_assessment(test_case, metrics, assertions)
      return unless test_case.expected_ekn_id
      
      ekn = Ekn.find(test_case.expected_ekn_id)
      
      # Determine assessment type based on test characteristics
      assessment_type = determine_assessment_type(test_case, assertions)
      
      # Create comprehensive assessment record
      MetaCreationAssessment.create!(
        ekn: ekn,
        mcp_test_run: @test_run,
        assessment_type: assessment_type,
        overall_score: assertions['overall_score'] || 0.0,
        assessment_status: :completed,
        evaluation_results: {
          'key_findings' => assertions['key_findings'] || [],
          'detailed_scores' => extract_detailed_scores(assertions),
          'test_context' => {
            'test_case' => test_case.name,
            'query' => test_case.expected_query,
            'tools_expected' => test_case.expected_tools
          }
        },
        meta_enliterator_performance: assertions['meta_enliterator_feedback'] || {},
        personality_health_metrics: extract_personality_metrics(metrics, assertions),
        improvement_recommendations: {
          'priority_items' => assertions['improvement_recommendations'] || [],
          'meta_enliterator_specific' => assertions.dig('meta_enliterator_feedback', 'tuning_suggestions') || []
        }
      )
      
      Rails.logger.info "Created meta-creation assessment for EKN #{ekn.slug}: #{assessment_type}"
      
    rescue => e
      Rails.logger.error "Failed to create meta-creation assessment: #{e.message}"
      # Don't fail the test run if assessment creation fails
    end
    
    private
    
    def determine_assessment_type(test_case, assertions)
      # Determine what type of assessment this represents based on test characteristics
      if assertions['personality_authenticity_score']
        if assertions['personality_evolution_healthy']
          :personality_development
        else
          :creation_guidance
        end
      elsif assertions['meta_enliterator_feedback'].present?
        :meta_learning
      else
        :user_satisfaction
      end
    end
    
    def extract_detailed_scores(assertions)
      {
        'framework_compliance' => assertions['framework_compliance_score'],
        'personality_authenticity' => assertions['personality_authenticity_score'],
        'semantic_relevance' => assertions['semantic_relevance_score'],
        'personality_evolution' => assertions['personality_evolution_score'],
        'overall_assessment' => assertions['overall_score']
      }
    end
    
    def extract_personality_metrics(metrics, assertions)
      {
        'consistency_score' => assertions['personality_authenticity_score'] || 0.0,
        'evolution_rate' => calculate_evolution_rate(assertions),
        'distinctiveness_score' => assertions.dig('detailed_assessment', 'personality_authenticity', 'score') || 0.0,
        'framework_alignment' => assertions['framework_compliance_score'] || 0.0,
        'response_quality' => assertions['semantic_relevance_score'] || 0.0
      }
    end
    
    def calculate_evolution_rate(assertions)
      # Calculate how much the EKN's personality is evolving
      # This would be more sophisticated in practice
      evolution_score = assertions['personality_evolution_score'] || 0.0
      
      # Map evolution score to evolution rate
      case evolution_score
      when 0.8..1.0 then 0.3  # Healthy, moderate evolution
      when 0.6..0.8 then 0.2  # Slow but positive evolution  
      when 0.4..0.6 then 0.1  # Minimal evolution
      else 0.0               # No meaningful evolution
      end
    end
  end
end