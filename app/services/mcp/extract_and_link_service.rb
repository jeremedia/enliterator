# frozen_string_literal: true

module Mcp
  # Service that implements the extract_and_link MCP tool using OpenAI Responses API
  # with Structured Outputs for guaranteed schema compliance
  class ExtractAndLinkService < ApplicationService
    EXTRACTION_MODES = %w[extract classify link].freeze
    DEFAULT_LINK_THRESHOLD = 0.6
    
    # Schema definitions for structured outputs
    ENTITY_SCHEMA = {
      type: "object",
      properties: {
        id: { type: "string" },
        pool: { 
          type: "string", 
          enum: %w[idea manifest experience relational evolutionary practical emanation lexicon intent spatial actor evidence risk method] 
        },
        canonical_name: { type: "string" },
        confidence: { type: "number", minimum: 0, maximum: 1 },
        surface_form: { type: "string" },
        context: { type: "string" }
      },
      required: %w[id pool canonical_name confidence surface_form],
      additionalProperties: false
    }.freeze
    
    AMBIGUITY_SCHEMA = {
      type: "object",
      properties: {
        text: { type: "string" },
        possible_pools: { type: "array", items: { type: "string" } },
        reason: { type: "string" }
      },
      required: %w[text possible_pools reason],
      additionalProperties: false
    }.freeze
    
    def initialize(text:, mode: "extract", link_threshold: DEFAULT_LINK_THRESHOLD)
      @text = text
      @mode = mode
      @link_threshold = link_threshold
      
      validate_inputs!
    end
    
    def call
      response = measure_time("entity_extraction") do
        extract_entities_with_structured_output
      end
      
      process_response(response)
    rescue StandardError => e
      log_error("Entity extraction failed", error: e)
      raise ServiceError, "Failed to extract entities: #{e.message}"
    end
    
    private
    
    attr_reader :text, :mode, :link_threshold
    
    def validate_inputs!
      raise ServiceError, "Text cannot be blank" if text.blank?
      raise ServiceError, "Invalid mode: #{mode}" unless EXTRACTION_MODES.include?(mode)
      raise ServiceError, "Link threshold must be between 0 and 1" unless link_threshold.between?(0, 1)
    end
    
    def extract_entities_with_structured_output
      messages = build_messages
      
      # CRITICAL: Using Responses API with Structured Outputs
      OPENAI.chat.completions.create(
        messages: messages,
        model: Rails.application.config.openai[:extraction_model],
        response_format: {
          type: "json_schema",
          json_schema: {
            name: "EntityExtraction",
            strict: true,  # REQUIRED for guaranteed schema compliance
            schema: {
              type: "object",
              properties: {
                entities: { type: "array", items: ENTITY_SCHEMA },
                ambiguities: { type: "array", items: AMBIGUITY_SCHEMA },
                normalized_query: { type: "string" }
              },
              required: %w[entities ambiguities normalized_query],
              additionalProperties: false
            }
          }
        },
        temperature: 0  # MUST be 0 for deterministic extraction
      )
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
    
    def process_response(response)
      parsed = JSON.parse(response.dig("choices", 0, "message", "content"))
      
      {
        entities: process_entities(parsed["entities"]),
        ambiguities: parsed["ambiguities"],
        normalized_query: parsed["normalized_query"],
        metadata: {
          mode: mode,
          link_threshold: link_threshold,
          model: response["model"],
          usage: response["usage"]
        }
      }
    end
    
    def process_entities(entities)
      entities.map do |entity|
        entity.merge(
          "linked" => should_link?(entity),
          "requires_rights_check" => requires_rights_check?(entity["pool"])
        )
      end
    end
    
    def should_link?(entity)
      mode == "link" && entity["confidence"] >= link_threshold
    end
    
    def requires_rights_check?(pool)
      %w[experience manifest].include?(pool)
    end
  end
end