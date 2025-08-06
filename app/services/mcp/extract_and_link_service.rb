# frozen_string_literal: true

module Mcp
  # Response model classes for structured extraction
  class ExtractedEntity < OpenAI::Helpers::StructuredOutput::BaseModel
    required :id, String, doc: "Unique identifier for the entity"
    required :pool, OpenAI::EnumOf[:idea, :manifest, :experience, :relational, :evolutionary, :practical, :emanation, :lexicon, :intent, :spatial, :actor, :evidence, :risk, :method], doc: "Pool classification"
    required :canonical_name, String, doc: "Canonical form of the entity name"
    required :confidence, Float, doc: "Extraction confidence (0-1)"
    required :surface_form, String, doc: "Entity as it appears in the text"
    required :context, String, nil?: true, doc: "Brief context around the entity"
  end
  
  class Ambiguity < OpenAI::Helpers::StructuredOutput::BaseModel
    required :text, String, doc: "The ambiguous text"
    required :possible_pools, Array, doc: "Potential pool classifications"
    required :reason, String, doc: "Explanation of the ambiguity"
  end
  
  class EntityExtractionResponse < OpenAI::Helpers::StructuredOutput::BaseModel
    required :entities, OpenAI::ArrayOf[ExtractedEntity], doc: "Extracted entities"
    required :ambiguities, OpenAI::ArrayOf[Ambiguity], doc: "Ambiguous extractions"
    required :normalized_query, String, doc: "Normalized version of the input query"
  end
  
  # Service that implements the extract_and_link MCP tool using OpenAI Responses API
  # with Structured Outputs for guaranteed schema compliance
  class ExtractAndLinkService < OpenaiConfig::BaseExtractionService
    EXTRACTION_MODES = %w[extract classify link].freeze
    DEFAULT_LINK_THRESHOLD = 0.6
    
    attr_reader :text, :mode, :link_threshold
    
    def initialize(text:, mode: "extract", link_threshold: DEFAULT_LINK_THRESHOLD)
      @text = text
      @mode = mode
      @link_threshold = link_threshold
    end
    
    def call
      super
    end
    
    protected
    
    def response_model_class
      EntityExtractionResponse
    end
    
    def validate_inputs!
      raise ArgumentError, "Text cannot be blank" if text.blank?
      raise ArgumentError, "Invalid mode: #{mode}" unless EXTRACTION_MODES.include?(mode)
      raise ArgumentError, "Link threshold must be between 0 and 1" unless link_threshold.between?(0, 1)
    end
    
    def content_for_extraction
      text
    end
    
    def transform_result(parsed_result)
      {
        entities: process_entities(parsed_result.entities),
        ambiguities: parsed_result.ambiguities.map(&:to_h),
        normalized_query: parsed_result.normalized_query,
        metadata: extraction_metadata.merge(
          mode: mode,
          link_threshold: link_threshold
        )
      }
    end
    
    def build_messages
      system_prompt = case mode
      when "extract"
        extract_mode_prompt
      when "classify"
        classify_mode_prompt
      when "link"
        link_mode_prompt
      end
      
      [
        { role: "system", content: system_prompt },
        { role: "user", content: text }
      ]
    end
    
    def extract_mode_prompt
      <<~PROMPT
        You are an entity extraction system for the Enliterator knowledge graph.
        Extract all entities from the text and classify them into the Ten Pool Canon:
        
        1. Idea - principles, theories, intents (the "why")
        2. Manifest - concrete instances, artifacts (the "what")
        3. Experience - lived outcomes, perceptions
        4. Relational - connections, lineages, networks
        5. Evolutionary - change over time
        6. Practical - how-to, tacit knowledge
        7. Emanation - ripple effects, influence
        8. Lexicon - definitions, terms
        9. Intent - user requests, tasks
        10. Spatial - locations (optional)
        11. Actor - people, organizations (optional)
        12. Evidence - primary data, measurements (optional)
        13. Risk - hazards, mitigations (optional)
        14. Method - methodologies, patterns (optional)
        
        For each entity:
        - Assign a unique ID
        - Determine the most appropriate pool
        - Extract the canonical name
        - Calculate confidence (0-1)
        - Include the surface form as it appears in text
        - Provide brief context
        
        Mark ambiguous entities that could belong to multiple pools.
        Normalize the query by standardizing terminology.
      PROMPT
    end
    
    def classify_mode_prompt
      <<~PROMPT
        You are a classification system. Classify the given text into one or more of the Ten Pool Canon categories.
        Focus on the dominant pool(s) the text represents.
        Return entities representing the classification with high confidence.
      PROMPT
    end
    
    def link_mode_prompt
      <<~PROMPT
        You are a linking system. Identify entities in the text that should be linked to existing knowledge graph nodes.
        Only return entities with confidence above #{link_threshold}.
        Focus on proper nouns, specific concepts, and canonical terms.
      PROMPT
    end
    
    private
    
    def process_entities(entities)
      entities.map do |entity|
        entity_hash = entity.to_h
        entity_hash.merge(
          linked: should_link?(entity),
          requires_rights_check: requires_rights_check?(entity.pool.to_s)
        )
      end
    end
    
    def should_link?(entity)
      mode == "link" && entity.confidence >= link_threshold
    end
    
    def requires_rights_check?(pool)
      %w[experience manifest].include?(pool)
    end
  end
end