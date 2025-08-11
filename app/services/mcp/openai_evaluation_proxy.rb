# frozen_string_literal: true

# OpenAI Evaluation Proxy - Fallback intelligent evaluation via OpenAI
#
# Since direct Claude Code API integration may not be available,
# this service uses OpenAI with structured outputs to simulate
# the intelligent evaluation capabilities that would be provided
# by Claude Code agents.
#
module Mcp
  class OpenaiEvaluationProxy < OpenaiConfig::BaseExtractionService
    attr_reader :test_case, :tool_calls, :ekn, :personality_profile
    
    def initialize(test_case, openai_response, tool_calls)
      @test_case = test_case
      @openai_response = openai_response
      @tool_calls = tool_calls.to_a
      @ekn = Ekn.find(test_case.expected_ekn_id) if test_case.expected_ekn_id
      @personality_profile = @ekn&.ekn_personality_profile
      
      super() # Initialize base service
    end
    
    def evaluate
      Rails.logger.info "Using OpenAI proxy for intelligent evaluation of EKN #{@ekn&.slug}"
      
      # Build evaluation context
      context = build_evaluation_context
      
      # Use OpenAI structured outputs for evaluation
      evaluation_response = call_with_structured_output(
        messages: [
          {
            role: "system", 
            content: build_evaluation_system_prompt(context)
          },
          {
            role: "user",
            content: build_evaluation_user_prompt(context)
          }
        ]
      )
      
      # Process structured response into metrics and assertions
      process_evaluation_response(evaluation_response)
    end
    
    protected
    
    def response_model_class
      EknEvaluationResponse
    end
    
    private
    
    def build_evaluation_context
      {
        'enliterator_framework' => build_framework_context,
        'ekn_personality' => build_ekn_context,
        'test_scenario' => build_test_context,
        'tool_results' => build_tool_results_context
      }
    end
    
    def build_evaluation_system_prompt(context)
      """
      You are an expert evaluator of Enliterated Knowledge Navigators (EKNs) within the Enliterator framework.
      
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
      
      Your task is to intelligently assess whether this EKN's response demonstrates:
      1. Proper understanding and application of the Enliterator framework (25% weight)
      2. Consistency with the EKN's established personality (30% weight)
      3. Semantic relevance and accuracy for the given query (25% weight)
      4. Healthy personality evolution and development (20% weight)
      
      Provide detailed, specific assessments with evidence and concrete recommendations.
      """
    end
    
    def build_evaluation_user_prompt(context)
      """
      Please evaluate this EKN's performance:
      
      EKN CONTEXT:
      #{context['ekn_personality']}
      
      TEST SCENARIO:
      #{context['test_scenario']}
      
      TOOL EXECUTION RESULTS:
      #{context['tool_results']}
      
      Provide a comprehensive evaluation following the structured format with specific evidence and actionable recommendations.
      """
    end
    
    def process_evaluation_response(response)
      # Convert OpenAI structured response to metrics and assertions format
      metrics = {
        "response_time_ms" => @tool_calls.sum(&:duration_ms) || 0,
        "tools_called_count" => @tool_calls.size,
        "tools_called" => @tool_calls.map(&:tool_name).uniq.sort,
        "intelligent_evaluation_score" => response.overall_score,
        "framework_compliance_score" => response.framework_compliance.score,
        "personality_authenticity_score" => response.personality_authenticity.score,
        "semantic_relevance_score" => response.semantic_relevance.score,
        "personality_evolution_score" => response.personality_evolution.score
      }
      
      assertions = {
        "all_assertions_passed" => response.overall_score >= 0.7,
        "intelligent_evaluation_passed" => response.overall_score >= 0.7,
        "framework_compliance_passed" => response.framework_compliance.score >= 0.7,
        "personality_authenticity_passed" => response.personality_authenticity.score >= 0.7,
        "semantic_relevance_passed" => response.semantic_relevance.score >= 0.7,
        "personality_evolution_healthy" => response.personality_evolution.score >= 0.6,
        
        "overall_score" => response.overall_score,
        "key_findings" => response.key_findings,
        "improvement_recommendations" => response.recommendations,
        "meta_enliterator_feedback" => {
          "guidance_effectiveness" => response.meta_enliterator_feedback.guidance_effectiveness,
          "tuning_suggestions" => response.meta_enliterator_feedback.tuning_suggestions
        },
        
        "detailed_assessment" => {
          "framework_compliance" => {
            "score" => response.framework_compliance.score,
            "assessment" => response.framework_compliance.assessment,
            "evidence" => response.framework_compliance.evidence,
            "issues" => response.framework_compliance.issues
          },
          "personality_authenticity" => {
            "score" => response.personality_authenticity.score,
            "assessment" => response.personality_authenticity.assessment,
            "evidence" => response.personality_authenticity.evidence,
            "issues" => response.personality_authenticity.issues
          },
          "semantic_relevance" => {
            "score" => response.semantic_relevance.score,
            "assessment" => response.semantic_relevance.assessment,
            "evidence" => response.semantic_relevance.evidence,
            "issues" => response.semantic_relevance.issues
          },
          "personality_evolution" => {
            "score" => response.personality_evolution.score,
            "assessment" => response.personality_evolution.assessment,
            "evidence" => response.personality_evolution.evidence,
            "issues" => response.personality_evolution.issues
          }
        }
      }
      
      [metrics, assertions]
    end
    
    # Helper methods to build context (simplified versions)
    
    def build_framework_context
      "Ten Pool Canon with canonical relationships and graph structure principles"
    end
    
    def build_ekn_context
      return "No EKN context available" unless @ekn && @personality_profile
      
      @personality_profile.evaluation_context
    end
    
    def build_test_context
      """
      Test Case: #{@test_case.name}
      Query: "#{@test_case.expected_query}"
      Expected EKN: #{@ekn&.slug} (##{@test_case.expected_ekn_id})
      Expected Tools: #{@test_case.expected_tools.join(' → ')}
      """
    end
    
    def build_tool_results_context
      return "No tool calls executed" if @tool_calls.empty?
      
      @tool_calls.map.with_index do |call, index|
        """
        Tool #{index + 1}: #{call.tool_name} (#{call.status})
        Response: #{format_response_data(call.response_data)}
        """
      end.join("\n\n")
    end
    
    def format_response_data(response_data)
      return "no response" unless response_data.present?
      
      if response_data.is_a?(Hash) && response_data['results']
        "#{response_data['results'].size} results returned"
      else
        response_data.to_s.truncate(200)
      end
    end
  end
end

# Structured output response model for OpenAI evaluation
class EknEvaluationResponse < OpenAI::Helpers::StructuredOutput::BaseModel
  required :overall_score, Float
  required :framework_compliance, FrameworkComplianceAssessment
  required :personality_authenticity, PersonalityAuthenticityAssessment
  required :semantic_relevance, SemanticRelevanceAssessment
  required :personality_evolution, PersonalityEvolutionAssessment
  required :key_findings, OpenAI::ArrayOf.new(String)
  required :recommendations, OpenAI::ArrayOf.new(String)
  required :meta_enliterator_feedback, MetaEnliteratorFeedback
end

class FrameworkComplianceAssessment < OpenAI::Helpers::StructuredOutput::BaseModel
  required :score, Float
  required :assessment, String
  required :evidence, OpenAI::ArrayOf.new(String)
  required :issues, OpenAI::ArrayOf.new(String)
end

class PersonalityAuthenticityAssessment < OpenAI::Helpers::StructuredOutput::BaseModel
  required :score, Float
  required :assessment, String
  required :evidence, OpenAI::ArrayOf.new(String)
  required :issues, OpenAI::ArrayOf.new(String)
end

class SemanticRelevanceAssessment < OpenAI::Helpers::StructuredOutput::BaseModel
  required :score, Float
  required :assessment, String
  required :evidence, OpenAI::ArrayOf.new(String)
  required :issues, OpenAI::ArrayOf.new(String)
end

class PersonalityEvolutionAssessment < OpenAI::Helpers::StructuredOutput::BaseModel
  required :score, Float
  required :assessment, String
  required :evidence, OpenAI::ArrayOf.new(String)
  required :issues, OpenAI::ArrayOf.new(String)
end

class MetaEnliteratorFeedback < OpenAI::Helpers::StructuredOutput::BaseModel
  required :guidance_effectiveness, String
  required :tuning_suggestions, OpenAI::ArrayOf.new(String)
end