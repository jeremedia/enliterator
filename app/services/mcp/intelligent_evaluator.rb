# frozen_string_literal: true

# MCP Intelligent Evaluator - EKN Personality and Meta-Creation Assessment Agent
#
# This service replaces basic quantitative scoring with intelligent semantic evaluation
# using Claude Code as a sub-agent. The evaluator understands both the Enliterator 
# framework and specific EKN personalities to assess:
#
# 1. Response quality and relevance within the Enliterator context
# 2. EKN personality consistency and development
# 3. Meta-enliterator creation guidance effectiveness
# 4. User-EKN relationship health and evolution
#
# Uses the Task tool to deploy specialized evaluation agents with deep domain knowledge.
#
module Mcp
  class IntelligentEvaluator
    # Use Rails logger instead of Loggable concern (which expects ActiveRecord model)
    # include Loggable
    
    attr_reader :test_case, :tool_calls, :ekn, :personality_profile, :intelligent_run
    
    def initialize(test_case, openai_response, tool_calls, test_run)
      @test_case = test_case
      @openai_response = openai_response
      @tool_calls = tool_calls.to_a
      @test_run = test_run
      @ekn = Ekn.find(test_case.expected_ekn_id) if test_case.expected_ekn_id
      @personality_profile = @ekn&.ekn_personality_profile
      
      # Create McpIntelligentTestRun for detailed logging
      @intelligent_run = McpIntelligentTestRun.create!(
        mcp_test_run: @test_run,
        mcp_test_case: @test_case,
        ekn: @ekn,
        status: :pending
      )
      
      @intelligent_run.log_info "Initialized IntelligentEvaluator for EKN #{@ekn&.slug} test case: #{test_case.name}"
    end
    
    # Main evaluation method - replaces basic TestAnalyzer
    def evaluate
      @intelligent_run.log_info "Starting intelligent evaluation for test case: #{test_case.name}"
      
      begin
        # Build comprehensive context for evaluation agent
        evaluation_context = build_evaluation_context
        
        # Deploy specialized evaluation agent via Task tool
        agent_results = deploy_evaluation_agent(evaluation_context)
        
        # Process agent results into standardized format
        metrics, assertions = process_evaluation_results(agent_results)
        
        # Complete the intelligent run with results
        @intelligent_run.complete!(assertions, assertions['overall_score'] || 0.0)
        
        [metrics, assertions]
        
      rescue => e
        @intelligent_run.fail!(e.message, { 'backtrace' => e.backtrace.first(3) })
        raise
      end
    end
    
    private
    
    def build_evaluation_context
      context = {
        'enliterator_framework' => build_framework_context,
        'ekn_personality' => build_ekn_context,
        'test_scenario' => build_test_context,
        'tool_execution_results' => build_tool_results_context,
        'evaluation_criteria' => build_evaluation_criteria
      }
      
      @intelligent_run.log_debug "Built evaluation context with #{context.keys.join(', ')}"
      context
    end
    
    def build_framework_context
      """
      ENLITERATOR FRAMEWORK KNOWLEDGE:
      
      Ten Pool Canon Structure:
      - Ideas: Conceptual knowledge, principles, theories
      - Manifestations: Physical implementations, structures, artifacts  
      - Experiences: Personal narratives, testimonials, subjective accounts
      - Processes: Procedures, workflows, methodologies
      - Outcomes: Results, consequences, impacts, measurements
      - Individuals: People, characters, personas, roles
      - Organizations: Groups, institutions, companies, movements
      - Locations: Places, geographies, spaces, environments
      - Temporal: Time periods, schedules, sequences, chronologies
      - Topical: Subject areas, themes, categories, domains
      
      Canonical Relationship Patterns:
      - Ideas → embodies → Manifestations (concepts become concrete)
      - Processes → produces → Outcomes (methods create results)  
      - Experiences → influences → Ideas (stories shape thinking)
      - Manifestations → elicits → Experiences (things create stories)
      - Organizations → implements → Processes (groups execute methods)
      
      Path Textization Rules:
      - Use canonical names consistently
      - Express relationships as "Entity(Type) → relationship → Entity(Type)"
      - Maintain Ten Pool categorization accuracy
      - Preserve provenance and rights information
      
      Knowledge Graph Principles:
      - Every entity has canonical identification
      - Relationships are bidirectional with forward/reverse forms
      - Spatial claims require explicit location evidence
      - Temporal connections need chronological validation
      """
    end
    
    def build_ekn_context
      return "No EKN context available" unless @ekn && @personality_profile
      
      profile_context = @personality_profile.evaluation_context
      
      additional_context = """
      EKN OPERATIONAL CONTEXT:
      - Total Knowledge Items: #{@ekn.ingest_items.count}
      - Active Since: #{@ekn.created_at.strftime('%Y-%m-%d')}
      - Recent Conversations: #{@ekn.conversations.where(created_at: 1.month.ago..).count}
      - Graph Density: #{calculate_graph_density}
      - Data Sources: #{extract_data_source_summary}
      
      #{profile_context}
      
      EXPECTED EKN BEHAVIOR:
      This EKN should respond in ways that:
      - Reflect its knowledge source characteristics
      - Maintain personality consistency across interactions
      - Leverage its Ten Pool preferences appropriately
      - Use its canonical vocabulary patterns
      - Connect concepts according to its relationship styles
      - Demonstrate growth while preserving core personality
      """
      
      additional_context
    end
    
    def build_test_context
      """
      TEST SCENARIO DETAILS:
      
      Test Case: #{test_case.name}
      Query: "#{test_case.expected_query}"
      Expected EKN: #{@ekn&.slug} (##{test_case.expected_ekn_id})
      Expected Tools: #{test_case.expected_tools.join(' → ')}
      
      Test Expectations:
      #{format_expectations(test_case.effective_expectations)}
      
      Variable Context:
      #{format_variables(test_case.effective_variables)}
      
      This test is evaluating whether the EKN:
      1. Responds appropriately to the specific query
      2. Maintains personality consistency
      3. Uses tools in the expected sequence and manner
      4. Provides results that align with its knowledge strengths
      5. Demonstrates healthy personality evolution
      """
    end
    
    def build_tool_results_context
      return "No tool calls executed" if @tool_calls.empty?
      
      results_summary = []
      
      @tool_calls.each_with_index do |call, index|
        result_summary = """
        TOOL CALL #{index + 1}: #{call.tool_name}
        Status: #{call.status}
        Arguments: #{format_arguments(call.arguments)}
        Execution Time: #{call.duration_ms}ms
        
        Response Data:
        #{format_response_data(call.response_data)}
        
        Success: #{call.status == 'completed'}
        """
        
        results_summary << result_summary
      end
      
      """
      TOOL EXECUTION ANALYSIS:
      
      Total Tools Called: #{@tool_calls.size}
      Successful Calls: #{@tool_calls.count { |c| c.status == 'completed' }}
      Failed Calls: #{@tool_calls.count { |c| c.status == 'failed' }}
      Total Execution Time: #{@tool_calls.sum(&:duration_ms) || 0}ms
      
      INDIVIDUAL TOOL RESULTS:
      #{results_summary.join("\n\n")}
      """
    end
    
    def build_evaluation_criteria
      """
      EVALUATION CRITERIA FOR EKN PERSONALITY AND PERFORMANCE:
      
      1. FRAMEWORK COMPLIANCE (Weight: 25%)
         - Proper Ten Pool usage and categorization
         - Canonical naming consistency
         - Relationship pattern adherence
         - Graph structure integrity
      
      2. PERSONALITY AUTHENTICITY (Weight: 30%)
         - Response matches EKN's established personality
         - Consistent voice and style
         - Appropriate domain expertise demonstration
         - Canonical vocabulary usage
      
      3. SEMANTIC RELEVANCE (Weight: 25%)
         - Results actually address the query intent
         - Information accuracy within EKN's knowledge base
         - Appropriate level of detail and specificity
         - Logical connection between query and response
      
      4. PERSONALITY EVOLUTION (Weight: 20%)
         - Healthy development of EKN capabilities
         - Maintaining distinctiveness while growing
         - Appropriate adaptation to user needs
         - Evidence of learning and improvement
      
      SCORING GUIDELINES:
      - 0.9-1.0: Excellent - Exemplary EKN behavior, perfect personality match
      - 0.7-0.89: Good - Solid performance with minor personality inconsistencies
      - 0.5-0.69: Acceptable - Basic functionality but personality needs attention
      - 0.3-0.49: Poor - Significant issues with personality or functionality
      - 0.0-0.29: Critical - Major problems requiring immediate attention
      """
    end
    
    def deploy_evaluation_agent(context)
      @intelligent_run.log_info "Deploying intelligent evaluation agent for EKN #{@ekn&.slug}"
      
      # Determine evaluator type and start the intelligent run
      evaluator_type = claude_code_api_available? ? :claude_code_api : :openai_proxy
      @intelligent_run.start!(evaluator_type, context)
      
      begin
        # Option 1: Try Claude Code API if configured
        if claude_code_api_available?
          @intelligent_run.log_info "Using Claude Code API for intelligent evaluation"
          agent_result = ClaudeCode::TaskClient.call(
            subagent_type: "general-purpose",
            description: "Evaluate EKN personality and response quality",
            prompt: build_agent_prompt(context)
          )
          
          @intelligent_run.log_info "Claude Code evaluation agent completed analysis"
          return agent_result
        end
        
        # Option 2: Use OpenAI structured outputs as proxy
        @intelligent_run.log_info "Using OpenAI proxy for intelligent evaluation"
        proxy_evaluator = Mcp::OpenaiEvaluationProxy.new(@test_case, @openai_response, @tool_calls)
        metrics, assertions = proxy_evaluator.evaluate
        
        # Convert to expected agent result format
        {
          "overall_score" => assertions['overall_score'],
          "framework_compliance" => assertions.dig('detailed_assessment', 'framework_compliance'),
          "personality_authenticity" => assertions.dig('detailed_assessment', 'personality_authenticity'),
          "semantic_relevance" => assertions.dig('detailed_assessment', 'semantic_relevance'),
          "personality_evolution" => assertions.dig('detailed_assessment', 'personality_evolution'),
          "key_findings" => assertions['key_findings'] || [],
          "recommendations" => assertions['improvement_recommendations'] || [],
          "meta_enliterator_feedback" => assertions['meta_enliterator_feedback'] || {}
        }.to_json
        
      rescue => e
        @intelligent_run.log_error "Intelligent evaluation failed: #{e.message}"
        @intelligent_run.log_error e.backtrace.first(3).join("\n")
        
        # Fallback to basic evaluation if all intelligent methods fail
        fallback_evaluation
      end
    end
    
    def build_agent_prompt(context)
      """
      You are an expert evaluator of Enliterated Knowledge Navigators (EKNs) within the Enliterator framework. 
      
      Your task is to intelligently assess whether this EKN's response demonstrates:
      1. Proper understanding and application of the Enliterator framework
      2. Consistency with the EKN's established personality
      3. Semantic relevance and accuracy for the given query
      4. Healthy personality evolution and development
      
      CONTEXT PROVIDED:
      #{context.map { |key, value| "#{key.upcase}:\n#{value}\n" }.join("\n")}
      
      EVALUATION TASK:
      Analyze the tool execution results and provide detailed assessment in the following format:
      
      {
        "overall_score": 0.85,
        "framework_compliance": {
          "score": 0.9,
          "assessment": "Excellent Ten Pool usage...",
          "evidence": ["specific examples"],
          "issues": ["any problems found"]
        },
        "personality_authenticity": {
          "score": 0.8,
          "assessment": "Response matches EKN personality well...",
          "evidence": ["personality consistency examples"],
          "issues": ["personality drift concerns"]
        },
        "semantic_relevance": {
          "score": 0.85,
          "assessment": "Results address query intent effectively...",
          "evidence": ["relevant response elements"],
          "issues": ["any relevance gaps"]
        },
        "personality_evolution": {
          "score": 0.9,
          "assessment": "Healthy development indicators...",
          "evidence": ["growth examples"],
          "issues": ["evolution concerns"]
        },
        "key_findings": [
          "Most important insights about this EKN's performance"
        ],
        "recommendations": [
          "Specific suggestions for improvement"
        ],
        "meta_enliterator_feedback": {
          "guidance_effectiveness": "Assessment of meta-creation guidance",
          "tuning_suggestions": ["Specific personality tuning recommendations"]
        }
      }
      
      Be thorough, specific, and focus on the EKN's personality authenticity and framework compliance.
      Your evaluation will be used to continuously improve both this specific EKN and the meta-enliterator's creation abilities.
      """
    end
    
    def process_evaluation_results(agent_results)
      begin
        # Parse agent results (assuming JSON response)
        evaluation_data = JSON.parse(agent_results.to_s)
        
        # Convert to standardized metrics and assertions format
        metrics = build_execution_metrics(evaluation_data)
        assertions = build_assertion_results(evaluation_data)
        
        @intelligent_run.log_info "Processed intelligent evaluation results: #{evaluation_data['overall_score']}"
        
        [metrics, assertions]
        
      rescue JSON::ParserError => e
        @intelligent_run.log_error "Failed to parse agent evaluation results: #{e.message}"
        
        # Fallback to basic evaluation
        fallback_evaluation
      end
    end
    
    def build_execution_metrics(evaluation_data)
      {
        "response_time_ms" => @tool_calls.sum(&:duration_ms) || 0,
        "tools_called_count" => @tool_calls.size,
        "tools_called" => @tool_calls.map(&:tool_name).uniq.sort,
        "successful_tools" => @tool_calls.count { |c| c.status == 'completed' },
        "failed_tools" => @tool_calls.count { |c| c.status == 'failed' },
        "intelligent_evaluation_score" => evaluation_data["overall_score"],
        "framework_compliance_score" => evaluation_data.dig("framework_compliance", "score"),
        "personality_authenticity_score" => evaluation_data.dig("personality_authenticity", "score"),
        "semantic_relevance_score" => evaluation_data.dig("semantic_relevance", "score"),
        "personality_evolution_score" => evaluation_data.dig("personality_evolution", "score")
      }
    end
    
    def build_assertion_results(evaluation_data)
      {
        "all_assertions_passed" => evaluation_data["overall_score"] >= 0.7,
        "intelligent_evaluation_passed" => evaluation_data["overall_score"] >= 0.7,
        "framework_compliance_passed" => evaluation_data.dig("framework_compliance", "score") >= 0.7,
        "personality_authenticity_passed" => evaluation_data.dig("personality_authenticity", "score") >= 0.7,
        "semantic_relevance_passed" => evaluation_data.dig("semantic_relevance", "score") >= 0.7,
        "personality_evolution_healthy" => evaluation_data.dig("personality_evolution", "score") >= 0.6,
        
        "overall_score" => evaluation_data["overall_score"],
        "key_findings" => evaluation_data["key_findings"] || [],
        "improvement_recommendations" => evaluation_data["recommendations"] || [],
        "meta_enliterator_feedback" => evaluation_data["meta_enliterator_feedback"] || {},
        
        "detailed_assessment" => {
          "framework_compliance" => evaluation_data["framework_compliance"],
          "personality_authenticity" => evaluation_data["personality_authenticity"], 
          "semantic_relevance" => evaluation_data["semantic_relevance"],
          "personality_evolution" => evaluation_data["personality_evolution"]
        }
      }
    end
    
    def claude_code_api_available?
      ENV['CLAUDE_CODE_API_KEY'].present? || ENV['CLAUDE_CODE_API_URL'].present?
    end
    
    def fallback_evaluation
      @intelligent_run.log_warn "Using fallback basic evaluation due to intelligent evaluation failure"
      
      # Simple fallback metrics
      basic_metrics = {
        "response_time_ms" => @tool_calls.sum(&:duration_ms) || 0,
        "tools_called_count" => @tool_calls.size,
        "successful_tools" => @tool_calls.count { |c| c.status == 'completed' },
        "fallback_evaluation" => true
      }
      
      basic_assertions = {
        "all_assertions_passed" => @tool_calls.all? { |c| c.status == 'completed' },
        "overall_score" => @tool_calls.any? ? (@tool_calls.count { |c| c.status == 'completed' }.to_f / @tool_calls.size) : 0.0,
        "fallback_mode" => true,
        "evaluation_error" => "Intelligent evaluation failed, using basic scoring",
        "key_findings" => ["Fallback evaluation - intelligent assessment unavailable"],
        "improvement_recommendations" => ["Configure intelligent evaluation system for detailed analysis"]
      }
      
      [basic_metrics, basic_assertions]
    end
    
    # Helper methods for context building
    
    def calculate_graph_density
      return "unknown" unless @ekn
      
      # Simplified graph density calculation
      # In reality, would query Neo4j for node/edge counts
      "moderate"
    end
    
    def extract_data_source_summary
      return "unknown" unless @ekn
      
      recent_batches = @ekn.ingest_batches.limit(3)
      source_types = recent_batches.map(&:name).join(", ")
      
      source_types.present? ? source_types : "mixed sources"
    end
    
    def format_expectations(expectations)
      expectations.map { |key, value| "- #{key.humanize}: #{value}" }.join("\n")
    end
    
    def format_variables(variables)
      variables.map { |key, value| "- #{key}: #{value}" }.join("\n")
    end
    
    def format_arguments(arguments)
      return "none" unless arguments.present?
      
      arguments.is_a?(Hash) ? arguments.inspect.truncate(200) : arguments.to_s.truncate(200)
    end
    
    def format_response_data(response_data)
      return "no response data" unless response_data.present?
      
      if response_data.is_a?(Hash)
        # Summarize key response elements
        summary_parts = []
        
        %w[results items entities].each do |key|
          if response_data[key].is_a?(Array)
            summary_parts << "#{key}: #{response_data[key].size} items"
          end
        end
        
        summary_parts.any? ? summary_parts.join(", ") : response_data.inspect.truncate(300)
      else
        response_data.to_s.truncate(300)
      end
    end
  end
end