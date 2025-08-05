# frozen_string_literal: true

module Pools
  # Model classes for structured relation extraction
  class EntityReference < OpenAI::Helpers::StructuredOutput::BaseModel
    required :pool_type, String, doc: "Pool type of the entity"
    required :label, String, doc: "Label/name of the entity"
    required :entity_index, Integer, nil?: true, doc: "Index in the entities array if referencing an extracted entity"
  end

  class ExtractedRelation < OpenAI::Helpers::StructuredOutput::BaseModel
    required :verb, String, doc: "Relation verb from the glossary"
    required :source, EntityReference, doc: "Source entity of the relation"
    required :target, EntityReference, doc: "Target entity of the relation"
    required :confidence, Float, doc: "Extraction confidence (0-1)"
    required :evidence, String, doc: "Text evidence supporting this relation"
  end

  class RelationExtractionResult < OpenAI::Helpers::StructuredOutput::BaseModel
    required :relations, Array, doc: "List of extracted relations"
    required :unmapped_relations, Array, doc: "Relations found but not matching glossary"
  end

  # Service to extract relations between entities using the Relation Verb Glossary
  class RelationExtractionService < ApplicationService
    
    attr_reader :content, :entities, :verb_glossary

    def initialize(content:, entities:, verb_glossary:)
      @content = content
      @entities = entities
      @verb_glossary = verb_glossary
    end

    def extract
      return { success: false, error: 'No entities provided' } if entities.empty?

      # Build the extraction prompt
      input_messages = build_input

      # Call OpenAI with Responses API
      response = OPENAI.responses.create(
        model: ENV.fetch('OPENAI_MODEL', 'gpt-4o-2024-08-06'),
        input: input_messages,
        text: RelationExtractionResult,
        temperature: 0  # Deterministic extraction
      )

      # Process the structured response
      result = response.output
        .flat_map { |output| output.content }
        .grep_v(OpenAI::Models::Responses::ResponseOutputRefusal)
        .first

      if result
        extraction = result.parsed
        
        # Transform and validate relations
        relations = transform_relations(extraction.relations)
        
        {
          success: true,
          relations: relations,
          unmapped_relations: extraction.unmapped_relations
        }
      else
        { success: false, error: 'No valid response from OpenAI' }
      end
    rescue StandardError => e
      Rails.logger.error "Relation extraction failed: #{e.message}"
      { success: false, error: e.message }
    end

    private

    def build_input
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

    def system_prompt
      <<~PROMPT
        You are a relation extraction specialist for the Enliterator system.
        Your task is to extract relations between entities using ONLY the approved Relation Verb Glossary.
        
        Approved Relations:
        #{format_verb_glossary}
        
        Guidelines:
        1. Only use verbs from the approved glossary
        2. Check that source and target pools match the verb requirements
        3. Look for explicit or strongly implied relationships in the text
        4. Include evidence quotes that support the relation
        5. Set confidence based on how clearly the relation is stated
        6. If you find relations that don't fit the glossary, list them as unmapped
        7. Consider both forward and reverse relations where applicable
        
        Entity Pool Types:
        - idea: principles, theories, concepts
        - manifest: concrete instances, artifacts, projects
        - experience: lived outcomes, testimonials, observations
        - relational: connections, networks, collaborations
        - evolutionary: changes, versions, timelines
        - practical: how-to knowledge, guides, procedures
        - emanation: influences, adoptions, downstream effects
      PROMPT
    end

    def user_prompt
      <<~PROMPT
        Extract relations between the following entities based on the content.
        Use ONLY the approved verb glossary.
        
        Entities Found:
        #{format_entities}
        
        Content:
        #{content.truncate(6000)}
        
        Look for relationships between these entities using the approved verbs.
        Include text evidence for each relation.
      PROMPT
    end

    def format_verb_glossary
      verb_glossary.map do |verb, config|
        source_desc = Array(config[:source]).join(' or ')
        target_desc = config[:target] == '*' ? 'any' : config[:target]
        reverse_desc = config[:reverse] ? " ↔ #{config[:reverse]}" : ''
        symmetric_desc = config[:symmetric] ? ' (symmetric)' : ''
        
        "- #{verb}: #{source_desc} → #{target_desc}#{reverse_desc}#{symmetric_desc}"
      end.join("\n")
    end

    def format_entities
      entities.each_with_index.map do |entity, index|
        "#{index}. [#{entity[:pool_type]}] #{entity[:attributes][:label]} - #{entity[:source_span].truncate(100)}"
      end.join("\n")
    end

    def transform_relations(relations)
      relations.filter_map do |relation|
        # Validate verb is in glossary
        verb_config = verb_glossary[relation.verb]
        next unless verb_config

        # Validate source and target pools match requirements
        next unless valid_pools?(relation, verb_config)

        {
          verb: relation.verb,
          source: resolve_entity_reference(relation.source),
          target: resolve_entity_reference(relation.target),
          confidence: relation.confidence,
          evidence: relation.evidence,
          path_text: build_path_text(relation)
        }
      end
    end

    def valid_pools?(relation, verb_config)
      source_pools = Array(verb_config[:source])
      target_pools = verb_config[:target] == '*' ? nil : Array(verb_config[:target])

      # Check source pool
      source_valid = source_pools.any? { |pool| pool.downcase == relation.source.pool_type.downcase }
      return false unless source_valid

      # Check target pool if specified
      if target_pools
        target_valid = target_pools.any? { |pool| pool.downcase == relation.target.pool_type.downcase }
        return false unless target_valid
      end

      true
    end

    def resolve_entity_reference(ref)
      # If entity_index is provided, use the extracted entity
      if ref.entity_index && entities[ref.entity_index]
        entity = entities[ref.entity_index]
        {
          pool_type: entity[:pool_type],
          label: entity[:attributes][:label],
          extracted_entity: entity
        }
      else
        # Otherwise, use the reference as-is
        {
          pool_type: ref.pool_type,
          label: ref.label
        }
      end
    end

    def build_path_text(relation)
      source_node = "#{relation.source.pool_type.capitalize}(#{relation.source.label})"
      target_node = "#{relation.target.pool_type.capitalize}(#{relation.target.label})"
      
      "#{source_node} → #{relation.verb} → #{target_node}"
    end
  end
end