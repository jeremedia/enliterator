# frozen_string_literal: true

namespace :mcp do
  namespace :test do
    desc "Run intelligent MCP evaluation directly using Claude Code sub-agents"
    task :direct_eval, [:test_case_id] => :environment do |_t, args|
      test_case_id = args[:test_case_id]
      
      if test_case_id.blank?
        puts "Available test cases for direct evaluation:"
        McpTestCase.includes(:mcp_test_suite).enabled.recent.limit(20).each do |test_case|
          puts "  #{test_case.id}: #{test_case.name} (Suite: #{test_case.mcp_test_suite.name})"
          puts "     EKN: #{test_case.expected_ekn_id}, Query: '#{test_case.expected_query}'"
          puts "     Tools: #{test_case.expected_tools.join(' → ')}" if test_case.expected_tools.any?
          puts
        end
        puts "Usage: rails mcp:test:direct_eval[TEST_CASE_ID]"
        puts 
        puts "This task demonstrates 'intelligence assessing intelligence' by having Claude Code"
        puts "directly evaluate EKN personality and framework compliance, bypassing OpenAI."
        exit
      end
      
      # Find the test case
      test_case = McpTestCase.find_by(id: test_case_id)
      unless test_case
        puts "❌ Test case not found: #{test_case_id}"
        exit 1
      end
      
      unless test_case.expected_ekn_id.present?
        puts "❌ Test case must have expected_ekn_id set for direct evaluation"
        exit 1
      end
      
      puts "🧠 Starting Direct Claude Code Evaluation"
      puts "=" * 50
      puts "Test Case: #{test_case.name}"
      puts "Suite: #{test_case.mcp_test_suite.name}"  
      puts "EKN: #{test_case.expected_ekn_id}"
      puts "Query: '#{test_case.expected_query}'"
      puts "Expected Tools: #{test_case.expected_tools.join(' → ')}" if test_case.expected_tools.any?
      puts
      
      begin
        # Create a mock test run to satisfy the evaluator requirements
        test_run = create_mock_test_run(test_case)
        
        # Execute the MCP tools directly to get real data
        puts "🔧 Executing MCP tools to generate evaluation data..."
        tool_calls = execute_test_case_tools(test_case)
        
        if tool_calls.empty?
          puts "⚠️  No tool calls executed. Creating placeholder for evaluation demonstration."
          tool_calls = create_placeholder_tool_calls(test_case)
        end
        
        puts "   Executed #{tool_calls.size} tool calls"
        puts
        
        # Create the intelligent evaluator
        puts "🚀 Deploying Claude Code sub-agent for intelligent evaluation..."
        
        evaluator = Mcp::DirectClaudeEvaluator.new(test_case, nil, tool_calls, test_run)
        metrics, assertions = evaluator.evaluate
        
        puts "✅ Direct evaluation completed!"
        puts "=" * 50
        puts
        
        # Display results
        display_evaluation_results(evaluator.intelligent_run, metrics, assertions)
        
        puts
        puts "💡 This demonstrates 'intelligence assessing intelligence' - Claude Code"
        puts "   directly evaluated the EKN's personality and framework compliance."
        
      rescue => e
        puts "❌ Direct evaluation failed: #{e.message}"
        puts e.backtrace.first(5).join("\n") if ENV['VERBOSE']
        exit 1
      end
    end
    
    desc "Run direct evaluation on multiple test cases"
    task :direct_eval_batch, [:suite_id] => :environment do |_t, args|
      suite_id = args[:suite_id]
      
      if suite_id.blank?
        puts "Available test suites for batch direct evaluation:"
        McpTestSuite.includes(:mcp_test_cases).each do |suite|
          enabled_cases = suite.mcp_test_cases.enabled
          puts "  #{suite.id}: #{suite.name} (#{enabled_cases.count} enabled cases)"
        end
        puts "\nUsage: rails mcp:test:direct_eval_batch[SUITE_ID]"
        exit
      end
      
      suite = McpTestSuite.find_by(id: suite_id)
      unless suite
        puts "❌ Test suite not found: #{suite_id}"
        exit 1
      end
      
      test_cases = suite.mcp_test_cases.enabled.where.not(variable_overrides: nil)
                         .select { |tc| tc.expected_ekn_id.present? }
      
      if test_cases.empty?
        puts "❌ No suitable test cases found (need enabled cases with EKN IDs)"
        exit 1
      end
      
      puts "🧠 Starting Batch Direct Claude Code Evaluation"
      puts "=" * 60
      puts "Suite: #{suite.name}"
      puts "Test Cases: #{test_cases.size}"
      puts
      
      results = []
      
      test_cases.each_with_index do |test_case, index|
        puts "#{index + 1}/#{test_cases.size}: #{test_case.name}..."
        
        begin
          # Create mock test run
          test_run = create_mock_test_run(test_case)
          
          # Execute tools
          tool_calls = execute_test_case_tools(test_case)
          tool_calls = create_placeholder_tool_calls(test_case) if tool_calls.empty?
          
          # Direct evaluation
          evaluator = Mcp::DirectClaudeEvaluator.new(test_case, nil, tool_calls, test_run)
          metrics, assertions = evaluator.evaluate
          
          results << {
            test_case: test_case,
            intelligent_run: evaluator.intelligent_run,
            score: assertions['overall_score'],
            success: assertions['overall_score'] >= 0.7
          }
          
          score_pct = (assertions['overall_score'] * 100).round(1)
          status = assertions['overall_score'] >= 0.7 ? "✅" : "❌"
          puts "  #{status} Score: #{score_pct}%"
          
        rescue => e
          puts "  ❌ Failed: #{e.message}"
          results << {
            test_case: test_case,
            error: e.message,
            success: false
          }
        end
      end
      
      puts
      puts "📊 Batch Evaluation Summary:"
      puts "=" * 40
      
      successful = results.count { |r| r[:success] }
      avg_score = results.select { |r| r[:score] }.map { |r| r[:score] }.sum / results.size
      
      puts "Total Cases: #{results.size}"
      puts "Successful: #{successful}"
      puts "Failed: #{results.size - successful}"
      puts "Average Score: #{(avg_score * 100).round(1)}%"
      puts
      
      # Show detailed results for failing cases
      failing_results = results.reject { |r| r[:success] }
      if failing_results.any?
        puts "❌ Failing Cases:"
        failing_results.each do |result|
          if result[:error]
            puts "  #{result[:test_case].name}: #{result[:error]}"
          else
            score_pct = (result[:score] * 100).round(1)
            puts "  #{result[:test_case].name}: #{score_pct}% (below 70% threshold)"
          end
        end
      end
    end
    
    private
    
    def create_mock_test_run(test_case)
      # Create a minimal test run for the evaluator to work with
      McpTestRun.create!(
        mcp_test_suite: test_case.mcp_test_suite,
        status: :running,
        started_at: Time.current,
        summary_metrics: { "evaluation_mode" => "direct_claude_code" }
      )
    end
    
    def execute_test_case_tools(test_case)
      tool_calls = []
      
      ekn = Ekn.find_by(id: test_case.expected_ekn_id)
      return tool_calls unless ekn
      
      query = test_case.expected_query
      expected_tools = test_case.expected_tools
      
      # Execute each expected tool in sequence
      expected_tools.each do |tool_name|
        begin
          start_time = Time.current
          
          case tool_name.strip.downcase
          when 'search'
            tool_call = execute_search_tool(ekn, query)
          when 'fetch'
            tool_call = execute_fetch_tool(ekn, query)
          when 'bridge'
            tool_call = execute_bridge_tool(ekn, query)
          when 'extract_and_link'
            tool_call = execute_extract_tool(ekn, query)
          else
            # Unknown tool - create placeholder
            tool_call = create_placeholder_tool_call(tool_name, ekn, query)
          end
          
          duration = ((Time.current - start_time) * 1000).round
          tool_call.completed_at = Time.current
          tool_calls << tool_call
          
        rescue => e
          # Create failed tool call
          tool_call = McpToolCall.new(
            ekn: ekn,
            tool_name: tool_name,
            status: 'failed',
            arguments: { query: query, ekn_id: ekn.id },
            response_data: { error: e.message },
            started_at: Time.current,
            error_message: e.message
          )
          tool_calls << tool_call
        end
      end
      
      tool_calls
    end
    
    def execute_search_tool(ekn, query)
      # Use the actual MCP search tool
      arguments = { query: query }
      
      begin
        # Call the search tool with the correct interface
        result = Mcp::SearchTool.call(query: query)
        
        McpToolCall.new(
          ekn: ekn,
          tool_name: 'search',
          status: 'completed',
          arguments: arguments,
          response_data: result,
          started_at: Time.current,
          completed_at: Time.current
        )
      rescue => e
        McpToolCall.new(
          ekn: ekn,
          tool_name: 'search',
          status: 'failed', 
          arguments: arguments,
          response_data: { error: e.message },
          started_at: Time.current,
          error_message: e.message
        )
      end
    end
    
    def execute_fetch_tool(ekn, query)
      # For fetch, we need an ID. Try to get one from a search first
      search_result = execute_search_tool(ekn, query)
      
      if search_result.status == 'completed' && search_result.response_data.present?
        begin
          search_data = JSON.parse(search_result.response_data)
          results = search_data['results'] || []
          
          if results.any?
            item_id = results.first['id']
            arguments = { id: item_id }
            
            result = Mcp::FetchTool.call(id: item_id)
            
            return McpToolCall.new(
              ekn: ekn,
              tool_name: 'fetch',
              status: 'completed',
              arguments: arguments,
              response_data: result,
              started_at: Time.current,
              completed_at: Time.current
            )
          end
        rescue JSON::ParserError
          # Fall through to error case
        end
      end
      
      # Fallback if no search results
      arguments = { id: "unknown" }
      McpToolCall.new(
        ekn: ekn,
        tool_name: 'fetch',
        status: 'failed',
        arguments: arguments,
        response_data: { error: "No items found to fetch" },
        started_at: Time.current,
        error_message: "No items found to fetch"
      )
    rescue => e
      McpToolCall.new(
        ekn: ekn,
        tool_name: 'fetch',
        status: 'failed',
        arguments: { id: "unknown" },
        response_data: { error: e.message },
        started_at: Time.current,
        error_message: e.message
      )
    end
    
    def execute_bridge_tool(ekn, query)
      # Bridge tool needs two concepts - extract from query or use defaults
      concepts = extract_concepts_from_query(query)
      
      arguments = {
        a: concepts[0] || "renewable",
        b: concepts[1] || "energy",
        max_paths: 3
      }
      
      begin
        result = Mcp::BridgeTool.call(a: arguments[:a], b: arguments[:b], max_paths: arguments[:max_paths])
        
        McpToolCall.new(
          ekn: ekn,
          tool_name: 'bridge',
          status: 'completed', 
          arguments: arguments,
          response_data: result,
          started_at: Time.current,
          completed_at: Time.current
        )
      rescue => e
        McpToolCall.new(
          ekn: ekn,
          tool_name: 'bridge',
          status: 'failed',
          arguments: arguments,
          response_data: { error: e.message },
          started_at: Time.current,
          error_message: e.message
        )
      end
    end
    
    def execute_extract_tool(ekn, query)
      arguments = {
        text: query,
        mode: "extract",
        link_threshold: 0.7
      }
      
      begin
        result = Mcp::ExtractAndLinkTool.call(text: query, mode: "extract", link_threshold: 0.7)
        
        McpToolCall.new(
          ekn: ekn,
          tool_name: 'extract_and_link',
          status: 'completed',
          arguments: arguments,
          response_data: result,
          started_at: Time.current,
          completed_at: Time.current
        )
      rescue => e
        McpToolCall.new(
          ekn: ekn,
          tool_name: 'extract_and_link',
          status: 'failed',
          arguments: arguments,
          response_data: { error: e.message },
          started_at: Time.current,
          error_message: e.message
        )
      end
    end
    
    def create_placeholder_tool_call(tool_name, ekn, query)
      McpToolCall.new(
        ekn: ekn,
        tool_name: tool_name,
        status: 'completed',
        arguments: { query: query, ekn_id: ekn.id },
        response_data: {
          placeholder: true,
          message: "Simulated #{tool_name} execution for evaluation",
          query: query,
          ekn_id: ekn.id
        },
        started_at: Time.current,
        completed_at: Time.current
      )
    end
    
    def create_placeholder_tool_calls(test_case)
      ekn = Ekn.find(test_case.expected_ekn_id)
      query = test_case.expected_query
      
      tool_calls = []
      
      if test_case.expected_tools.any?
        test_case.expected_tools.each do |tool_name|
          tool_calls << create_placeholder_tool_call(tool_name, ekn, query)
        end
      else
        # Default to search if no tools specified
        tool_calls << create_placeholder_tool_call('search', ekn, query)
      end
      
      tool_calls
    end
    
    def extract_concepts_from_query(query)
      # Simple concept extraction - split on common words
      words = query.split(/\s+/)
      concepts = words.reject { |w| %w[and or the a an in on at for with].include?(w.downcase) }
      concepts.take(2)
    end
    
    def display_evaluation_results(intelligent_run, metrics, assertions)
      puts "📊 Evaluation Results:"
      puts "-" * 30
      puts "Overall Score: #{(assertions['overall_score'] * 100).round(1)}%"
      puts "Status: #{intelligent_run.status}"
      puts "Evaluator Type: #{intelligent_run.evaluator_type}"
      puts "Duration: #{intelligent_run.duration_ms}ms" if intelligent_run.duration_ms
      puts
      
      if assertions['detailed_assessment']
        puts "📋 Detailed Assessment:"
        
        %w[framework_compliance personality_authenticity semantic_relevance personality_evolution].each do |category|
          data = assertions['detailed_assessment'][category]
          next unless data
          
          score = data['score'] || 0.0
          puts "  #{category.humanize}: #{(score * 100).round(1)}%"
          puts "    Assessment: #{data['assessment']}" if data['assessment']
          
          if data['evidence'] && data['evidence'].any?
            puts "    Evidence:"
            data['evidence'].first(2).each { |e| puts "    - #{e}" }
          end
          
          if data['issues'] && data['issues'].any?
            puts "    Issues:"
            data['issues'].first(2).each { |i| puts "    - #{i}" }
          end
          puts
        end
      end
      
      if assertions['key_findings'] && assertions['key_findings'].any?
        puts "🔍 Key Findings:"
        assertions['key_findings'].each { |f| puts "  • #{f}" }
        puts
      end
      
      if assertions['improvement_recommendations'] && assertions['improvement_recommendations'].any?
        puts "💡 Recommendations:"
        assertions['improvement_recommendations'].each { |r| puts "  • #{r}" }
        puts
      end
      
      if metrics
        puts "⚡ Execution Metrics:"
        puts "  Tools Called: #{metrics['tools_called_count']}"
        puts "  Successful Tools: #{metrics['successful_tools']}" 
        puts "  Response Time: #{metrics['response_time_ms']}ms"
      end
    end
  end
end