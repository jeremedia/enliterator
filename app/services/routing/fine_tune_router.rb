# frozen_string_literal: true

module Routing
  # Routes queries through fine-tuned model for intent classification and normalization
  class FineTuneRouter < OpenaiConfig::BaseExtractionService
    # Tool parameters model
    class ToolParams < OpenAI::Helpers::StructuredOutput::BaseModel
      required :query, String, nil?: true, doc: "Search query"
      required :id, String, nil?: true, doc: "Entity ID for fetch"
      required :top_k, Integer, nil?: true, doc: "Number of results"
      required :pools, OpenAI::ArrayOf[String], nil?: true, doc: "Pool filters"
      required :require_rights, String, nil?: true, doc: "Rights level: public|internal|any"
      required :include_relations, OpenAI::Boolean, nil?: true, doc: "Include relations in fetch"
      required :relation_depth, Integer, nil?: true, doc: "Depth of relations to fetch"
      required :a, String, nil?: true, doc: "First entity for bridge"
      required :b, String, nil?: true, doc: "Second entity for bridge"
      required :text, String, nil?: true, doc: "Text to extract from"
      required :mode, String, nil?: true, doc: "Extraction mode"
    end
    
    # Response model for routing decisions
    class RoutingDecision < OpenAI::Helpers::StructuredOutput::BaseModel
      required :normalized_query, String, doc: "Query normalized with canonical terms"
      required :canonical_entities, OpenAI::ArrayOf[String], doc: "Canonical entity names detected"
      required :detected_pools, OpenAI::ArrayOf[String], doc: "Ten Pool Canon pools referenced"
      required :primary_tool, String, doc: "Primary MCP tool to use: search|fetch|bridge|extract_and_link"
      required :tool_params, ToolParams, doc: "Parameters for the selected tool"
      required :confidence, Float, doc: "Confidence in routing decision (0-1)"
      required :reasoning, String, doc: "Brief explanation of routing decision"
    end
    
    attr_reader :query, :context, :ekn
    
    def initialize(query:, ekn: nil, context: nil)
      @query = query
      @ekn = ekn
      @context = context || {}
    end
    
    def call
      Rails.logger.info "FineTuneRouter.call starting"
      begin
        super
      rescue ArgumentError => e
        Rails.logger.error "ArgumentError in FineTuneRouter: #{e.message}"
        Rails.logger.error e.backtrace.first(10).join("\n")
        raise
      end
    end
    
    protected
    
    def response_model_class
      RoutingDecision
    end
    
    def build_messages
      [
        {
          role: "system",
          content: system_prompt
        },
        {
          role: "user", 
          content: user_prompt
        }
      ]
    end
    
    def system_prompt
      <<~PROMPT
        You are a routing assistant for the Enliterator Knowledge Navigator.
        Analyze queries and route them to the appropriate MCP tool.
        
        Available tools:
        - search: Find entities matching a query
        - fetch: Get complete details about a specific entity
        - bridge: Find paths connecting entities
        - extract_and_link: Extract entities from text
        
        Ten Pool Canon: Idea, Practical, Experience, Manifest, Character, Time, Space, Lifecycle, Symbolic, Relator
      PROMPT
    end
    
    def user_prompt
      content_for_extraction
    end
    
    def model_for_task
      # Use the fine-tuned model for routing
      OpenaiSetting.get('model_routing') || 'ft:gpt-4.1-mini-2025-04-14:chds:enliterator-v20250806:C1Xw7rmy'
    end
    
    def temperature_for_task
      0.0  # Deterministic routing
    end
    
    def content_for_extraction
      <<~CONTENT
        Analyze and route this query for the Enliterator Knowledge Navigator.
        
        Query: #{@query}
        
        Context:
        - EKN: #{@ekn&.name || 'Meta-Enliterator'}
        - Previous entities: #{@context[:previous_entities]&.join(', ') || 'none'}
        
        Available tools:
        1. search - Semantic and graph search for entities
        2. fetch - Get complete details about a specific entity
        3. bridge - Find paths connecting two entities
        4. extract_and_link - Extract entities from provided text
        
        Ten Pool Canon:
        - Idea: Concepts, principles, philosophies
        - Practical: Methods, processes, techniques
        - Experience: Stories, testimonials, personal accounts
        - Manifest: Physical/digital artifacts, documents
        - Character: People, agents, roles
        - Time: Temporal entities, events, periods
        - Space: Locations, places, geographic entities
        - Lifecycle: States, transitions, progressions
        - Symbolic: Symbols, meanings, representations
        - Relator: Relationships, connections
        
        Instructions:
        1. Identify canonical entities and their pools
        2. Normalize the query using canonical terms
        3. Select the most appropriate tool
        4. Provide specific parameters for that tool
        5. Consider the context and previous interactions
      CONTENT
    end
    
    def transform_result(parsed_result)
      # Convert ToolParams object to hash
      params = parsed_result.tool_params.to_h.compact
      
      # Add defaults based on tool
      case parsed_result.primary_tool
      when 'search'
        params[:top_k] ||= 10
        params[:require_rights] ||= 'public'
        params[:query] ||= @query
      when 'fetch'
        params[:include_relations] = true if params[:include_relations].nil?
        params[:relation_depth] ||= 2
      when 'bridge'
        params[:top_k] ||= 10
      when 'extract_and_link'
        params[:mode] ||= 'extract'
        params[:text] ||= @query
      end
      
      {
        query: @query,
        normalized_query: parsed_result.normalized_query,
        canonical_entities: parsed_result.canonical_entities.to_a,
        detected_pools: parsed_result.detected_pools.to_a,
        primary_tool: parsed_result.primary_tool,
        tool_params: params,
        confidence: parsed_result.confidence,
        reasoning: parsed_result.reasoning,
        routed_at: Time.current
      }
    end
  end
end