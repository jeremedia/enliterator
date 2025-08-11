# frozen_string_literal: true

namespace :mcp do
  namespace :test do
    desc "Run MCP test suite by name or ID"
    task :run, [:suite_identifier] => :environment do |_t, args|
      suite_identifier = args[:suite_identifier]
      
      if suite_identifier.blank?
        puts "Available test suites:"
        McpTestSuite.all.each do |suite|
          status = suite.ready_to_run? ? "✅ Ready" : "❌ Not Ready"
          puts "  #{suite.id}: #{suite.name} - #{suite.enabled_test_cases_count} cases (#{status})"
        end
        puts "\nUsage: rails mcp:test:run[SUITE_NAME_OR_ID]"
        exit
      end
      
      # Find suite by name or ID
      suite = McpTestSuite.find_by(name: suite_identifier) || 
              McpTestSuite.find_by(id: suite_identifier.to_i)
      
      unless suite
        puts "❌ Test suite not found: #{suite_identifier}"
        exit 1
      end
      
      puts "🚀 Running MCP test suite: #{suite.name}"
      puts "   Saved Prompt ID: #{suite.saved_prompt_id}"
      puts "   Test Cases: #{suite.enabled_test_cases_count}"
      puts
      
      begin
        runner = Mcp::TestRunner.new(suite)
        test_run = runner.execute_suite
        
        puts "✅ Test run completed!"
        puts "   Run ID: #{test_run.id}"
        puts "   Status: #{test_run.status}"
        puts "   Success Rate: #{test_run.success_rate}%"
        puts "   Duration: #{test_run.formatted_duration}"
        
        if test_run.summary_metrics
          metrics = test_run.summary_metrics
          puts "   Total Cases: #{metrics['total_cases']}"
          puts "   Passed: #{metrics['passed']}"
          puts "   Failed: #{metrics['failed']}"
          puts "   Avg Response Time: #{metrics['avg_response_time_ms']}ms"
        end
        
      rescue => e
        puts "❌ Test run failed: #{e.message}"
        puts e.backtrace.first(3).join("\n") if ENV['VERBOSE']
        exit 1
      end
    end
    
    desc "Run all MCP test suites"
    task :run_all => :environment do
      suites = McpTestSuite.where(id: McpTestSuite.enabled.select(:id))
      
      if suites.empty?
        puts "No test suites ready to run"
        exit
      end
      
      puts "🚀 Running #{suites.count} MCP test suites..."
      puts
      
      results = []
      
      suites.each do |suite|
        puts "Running: #{suite.name}..."
        
        begin
          runner = Mcp::TestRunner.new(suite)
          test_run = runner.execute_suite
          
          results << {
            suite: suite,
            test_run: test_run,
            success: test_run.status_completed?
          }
          
          puts "  ✅ #{test_run.success_rate}% success rate"
          
        rescue => e
          results << {
            suite: suite,
            error: e.message,
            success: false
          }
          puts "  ❌ Failed: #{e.message}"
        end
      end
      
      puts
      puts "📊 Summary:"
      successful = results.count { |r| r[:success] }
      puts "  Total Suites: #{results.count}"
      puts "  Successful: #{successful}"
      puts "  Failed: #{results.count - successful}"
      
      if results.any? { |r| !r[:success] }
        exit 1
      end
    end
    
    desc "Create a sample MCP test suite for demonstration"
    task :create_sample => :environment do
      # Check if we have EKNs to test
      ekns = Ekn.limit(3)
      if ekns.empty?
        puts "❌ No EKNs found. Need at least one EKN to create sample tests."
        exit 1
      end
      
      puts "🔧 Creating sample MCP test suite..."
      
      # Create test suite
      suite = McpTestSuite.create!(
        name: "Sample MCP Test Suite",
        saved_prompt_id: "pmpt_sample_123", # This would be a real OpenAI saved prompt ID
        description: "Sample test suite demonstrating MCP test automation across multiple EKNs and tools",
        base_variables: {
          "SYSTEM_PROMPT" => "You are testing EKN {EKN_ID}. Use the {TOOL_SEQUENCE} tools to answer: '{QUERY}'. Include _metadata with ekn_id for proper targeting.",
          "TOOL_SEQUENCE" => "search",
          "QUERY" => "renewable energy"
        },
        test_config: {
          "timeout" => 30,
          "max_retries" => 2,
          "concurrent_executions" => 1
        }
      )
      
      # Create test cases for different EKNs and tool combinations
      test_cases = []
      
      ekns.each_with_index do |ekn, index|
        # Simple search test
        test_cases << McpTestCase.create!(
          mcp_test_suite: suite,
          name: "Search Test - EKN #{ekn.id}",
          description: "Test basic search functionality on EKN #{ekn.slug}",
          variable_overrides: {
            "EKN_ID" => ekn.id.to_s,
            "QUERY" => "renewable energy processes",
            "TOOL_SEQUENCE" => "search"
          },
          expectations: {
            "tools_called" => ["search"],
            "min_results" => 1,
            "max_response_time_ms" => 10000,
            "min_success_rate" => 90.0
          }
        )
        
        # Multi-tool test (if we have multiple tools)
        if index == 0 # Only create complex test for first EKN
          test_cases << McpTestCase.create!(
            mcp_test_suite: suite,
            name: "Multi-tool Test - EKN #{ekn.id}",
            description: "Test search + fetch combination on EKN #{ekn.slug}",
            variable_overrides: {
              "EKN_ID" => ekn.id.to_s,
              "QUERY" => "climate change outcomes",
              "TOOL_SEQUENCE" => "search,fetch"
            },
            expectations: {
              "tools_called" => ["search", "fetch"],
              "min_results" => 1,
              "max_response_time_ms" => 15000,
              "min_success_rate" => 80.0
            }
          )
        end
      end
      
      puts "✅ Created sample test suite: #{suite.name}"
      puts "   Suite ID: #{suite.id}"
      puts "   Test Cases: #{test_cases.count}"
      puts "   EKNs Covered: #{ekns.map(&:slug).join(', ')}"
      puts
      puts "⚠️  NOTE: This uses a dummy saved prompt ID (pmpt_sample_123)."
      puts "   You'll need to:"
      puts "   1. Create a real OpenAI saved prompt"
      puts "   2. Update the saved_prompt_id in the test suite"
      puts "   3. Configure your OpenAI API key"
      puts
      puts "To run: rails mcp:test:run[#{suite.id}]"
    end
    
    desc "Show MCP test results for a test run"
    task :results, [:run_id] => :environment do |_t, args|
      run_id = args[:run_id]
      
      if run_id.blank?
        puts "Recent test runs:"
        McpTestRun.includes(:mcp_test_suite).recent.limit(10).each do |run|
          status_icon = run.status_completed? ? "✅" : "❌"
          puts "  #{run.id}: #{run.mcp_test_suite.name} - #{run.status} #{status_icon} (#{run.created_at.strftime('%Y-%m-%d %H:%M')})"
        end
        puts "\nUsage: rails mcp:test:results[RUN_ID]"
        exit
      end
      
      test_run = McpTestRun.find_by(id: run_id)
      unless test_run
        puts "❌ Test run not found: #{run_id}"
        exit 1
      end
      
      executions = test_run.mcp_test_executions.includes(:mcp_test_case, :mcp_tool_calls)
      
      puts "📋 Test Run Results: #{test_run.mcp_test_suite.name}"
      puts "   Run ID: #{test_run.id}"
      puts "   Status: #{test_run.status}"
      puts "   Started: #{test_run.started_at&.strftime('%Y-%m-%d %H:%M:%S')}"
      puts "   Completed: #{test_run.completed_at&.strftime('%Y-%m-%d %H:%M:%S')}"
      puts "   Duration: #{test_run.formatted_duration}"
      puts "   Success Rate: #{test_run.success_rate}%"
      puts
      
      if test_run.summary_metrics
        metrics = test_run.summary_metrics
        puts "📊 Summary Metrics:"
        puts "   Total Cases: #{metrics['total_cases']}"
        puts "   Passed: #{metrics['passed']}"
        puts "   Failed: #{metrics['failed']}"
        puts "   Avg Response Time: #{metrics['avg_response_time_ms']}ms"
        puts "   Total Tool Calls: #{metrics['total_tool_calls']}"
        puts
      end
      
      puts "📋 Test Case Results:"
      executions.each do |execution|
        status_icon = case execution.status
        when 'completed'
          execution.all_assertions_passed? ? "✅" : "⚠️"
        when 'failed'
          "❌"
        else
          "⏳"
        end
        
        puts "  #{status_icon} #{execution.mcp_test_case.name}"
        puts "     Status: #{execution.status}"
        puts "     Duration: #{execution.formatted_duration}"
        
        if execution.execution_metrics
          metrics = execution.execution_metrics
          puts "     Tools Called: #{metrics['tools_called']&.join(', ')}"
          puts "     Response Time: #{metrics['response_time_ms']}ms" if metrics['response_time_ms']
        end
        
        if execution.assertion_results && !execution.all_assertions_passed?
          puts "     Failed Assertions:"
          execution.assertion_results.each do |key, value|
            if key.end_with?('_met', '_passed', '_called') && value == false
              puts "       - #{key.humanize}: #{value}"
            end
          end
        end
        
        puts "     Tool Calls: #{execution.mcp_tool_calls.count}"
        puts
      end
    end
    
    desc "Clean up old test runs (keeps last 50)"
    task :cleanup => :environment do
      old_runs = McpTestRun.order(created_at: :desc).offset(50)
      count = old_runs.count
      
      if count > 0
        puts "🧹 Cleaning up #{count} old test runs..."
        old_runs.destroy_all
        puts "✅ Cleanup complete"
      else
        puts "✅ No cleanup needed - fewer than 50 test runs exist"
      end
    end
  end
end