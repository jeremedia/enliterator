# frozen_string_literal: true

module Pools
  # Model-Driven Entity Extraction Service
  #
  # Generates extraction prompts dynamically from model configurations,
  # ensuring perfect consistency between model schema and extraction expectations.
  #
  # This service replaces hardcoded prompts with live schema-driven prompts
  # that automatically stay in sync with model reality.
  #
  class ModelDrivenExtractionService < OpenaiConfig::BaseExtractionService
    
    # All pool models that support extraction
    POOL_MODELS = [
      # Tier 1: Core Entity Pools (COMPLETE - Model-Driven Architecture)
      Actor,           # ActorAndRole - People and organizations
      Spatial,         # Spatial - Places and locations  
      MethodPool,      # MethodAndModel - Research methods
      Evidence,        # EvidenceAndObservation - Data and observations
      Risk,            # RiskAndGovernance - Safety and compliance
      
      # Tier 2: Relationship Pools (COMPLETE - Model-Driven Architecture)
      Relational,            # Relational - Connections and networks
      ProvenanceAndRights,   # ProvenanceAndRights - Source attribution
      Evolutionary,          # Evolutionary - Change over time
      
      # Tier 3: Semantic Pools (COMPLETE - Model-Driven Architecture)
      LexiconAndOntology,    # LexiconAndOntology - Definitions and terminology
      IntentAndTask,         # IntentAndTask - User goals and delivery preferences
      Idea,                  # Idea - Principles, theories, concepts
      
      # Tier 4: Content Pools (COMPLETE - Model-Driven Architecture) 🎉
      Manifest,              # Manifest - Concrete artifacts and implementations
      Experience,            # Experience - Lived outcomes and human perspectives
      Practical,             # Practical - How-to knowledge and procedures
      Emanation,             # Emanation - Ripple effects and influence patterns
    ].freeze

    attr_reader :content, :lexicon_context, :source_metadata

    def initialize(content:, lexicon_context: [], source_metadata: {})
      @content = content
      @lexicon_context = lexicon_context
      @source_metadata = source_metadata
    end

    def call
      super
    end

    alias extract call

    protected

    def response_model_class
      ModelDrivenExtractionResult
    end

    def validate_inputs!
      raise ArgumentError, 'Content is required' if content.blank?
    end

    def content_for_extraction
      user_prompt
    end

    def transform_result(parsed_result)
      entities = transform_entities(parsed_result.entities)
      
      {
        success: true,
        entities: entities,
        metadata: {
          extraction_strategy: 'model_driven',
          pools_available: POOL_MODELS.size,
          pools_extracted: entities.map { |e| e[:pool_type] }.uniq.size,
          extraction_time: Time.current
        }.merge(extraction_metadata)
      }
    end

    def build_messages
      [
        {
          role: :system,
          content: system_prompt
        },
        {
          role: :user,
          content: user_prompt
        }
      ]
    end

    private

    def system_prompt
      <<~PROMPT
        You are an expert entity extraction specialist for the Enliterator Knowledge Navigator system.
        Your task is to extract entities that belong to the Ten Pool Canon framework using LIVE MODEL SCHEMAS.
        
        CRITICAL: The extraction schemas below are generated directly from the database models.
        All enum values, field types, and validation rules are LIVE and reflect current system reality.
        
        #{generate_pool_sections}
        
        ## EXTRACTION STRATEGY:
        1. Read the entire text for context
        2. Identify entities and their roles in sentences  
        3. Classify based on function and context, not just category
        4. Use EXACT enum values from the schemas above
        5. Provide detailed reasoning for classification decisions
        6. Aim for balanced distribution across applicable pools
        
        ## CRITICAL RULES:
        - Only use enum values specified in the schemas (they are live from the database)
        - Set confidence based on clarity and context (0.0-1.0)
        - Each entity should have pool-appropriate attributes
        - Merge similar references, don't duplicate entities
        - Consider all pools systematically - optional pools are only optional when content lacks those entity types
      PROMPT
    end

    def user_prompt
      <<~PROMPT
        Extract entities from the following content using the Ten Pool Canon framework.
        Focus on clear, well-defined entities that can become nodes in a knowledge graph.
        Use the LIVE SCHEMAS provided in the system prompt - all enum values are current.
        
        Content to analyze:
        #{content.truncate(8000)}
        
        Source metadata: #{source_metadata.to_json}
        
        Lexicon context (prefer these canonical terms):
        #{format_lexicon_context}
      PROMPT
    end

    def generate_pool_sections
      POOL_MODELS.map do |model|
        next unless model.respond_to?(:extraction_config)
        
        begin
          config = model.extraction_config
          config.to_extraction_prompt_section
        rescue => e
          Rails.logger.warn "Failed to generate extraction section for #{model.name}: #{e.message}"
          "### #{model.name.upcase}\n**Configuration error - please check model setup**\n"
        end
      end.compact.join("\n\n")
    end

    def format_lexicon_context
      return "None available" if lexicon_context.empty?
      
      lexicon_context.map do |term_info|
        case term_info
        when Array
          "- #{term_info[0]} (#{term_info[1]}): #{term_info[2]}"
        when Hash
          "- #{term_info[:term]} (#{term_info[:pool]}): #{term_info[:description]}"
        else
          "- #{term_info}"
        end
      end.join("\n")
    end

    def transform_entities(entities)
      entities.map do |entity|
        {
          pool_type: entity.pool_type,
          confidence: entity.confidence,
          attributes: entity.attributes.to_h,
          lexicon_match: entity.lexicon_match,
          source_span: entity.source_span,
          extraction_method: 'model_driven'
        }
      end
    end
  end

  # Response model for structured output
  class ModelDrivenEntityAttributes < OpenAI::Helpers::StructuredOutput::BaseModel
    # This will be dynamically populated based on the pool type
    # For now, we'll use a flexible approach with common fields
    required :name, String, doc: "The primary identifier or name of the entity"
    required :description, String, nil?: true, doc: "Description or additional context"
    required :role, String, nil?: true, doc: "Role or type classification (use exact enum values)"
    required :location_name, String, nil?: true, doc: "Location name for spatial entities"
    required :method_name, String, nil?: true, doc: "Method name for method entities"
    required :evidence_type, String, nil?: true, doc: "Evidence type for evidence entities"
    required :risk_type, String, nil?: true, doc: "Risk type for risk entities"
    required :severity, String, nil?: true, doc: "Severity level for risk entities (use exact enum values)"
  end

  class ModelDrivenExtractedEntity < OpenAI::Helpers::StructuredOutput::BaseModel
    required :pool_type, String, doc: "Pool type using exact canonical name from model config"
    required :confidence, Float, doc: "Extraction confidence (0.0-1.0)"
    required :attributes, ModelDrivenEntityAttributes, doc: "Entity-specific attributes"
    required :lexicon_match, String, nil?: true, doc: "Matched canonical term from lexicon"
    required :source_span, String, doc: "Text span this entity was extracted from"
  end

  class ModelDrivenExtractionResult < OpenAI::Helpers::StructuredOutput::BaseModel
    required :entities, OpenAI::ArrayOf[ModelDrivenExtractedEntity], doc: "List of extracted entities"
    required :extraction_notes, String, nil?: true, doc: "Notes about the extraction process"
  end
end