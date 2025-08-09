# frozen_string_literal: true

module Pools
  # Model classes for structured relation extraction
  class RelationEntity < OpenAI::Helpers::StructuredOutput::BaseModel
    required :pool_type, String, doc: "The pool type of the entity"
    required :label, String, doc: "The label/name of the entity"
    required :id, String, nil?: true, doc: "The entity ID if available"
  end
  
  class ExtractedRelation < OpenAI::Helpers::StructuredOutput::BaseModel
    required :source, RelationEntity
    required :verb, String, doc: "Relationship verb from glossary"
    required :target, RelationEntity
    required :evidence_span, String, nil?: true, doc: "Text evidence for relationship"
    required :confidence, Float, doc: "Confidence score (0-1)"
  end
  
  class RelationExtractionResult < OpenAI::Helpers::StructuredOutput::BaseModel
    required :relations, OpenAI::ArrayOf[ExtractedRelation], doc: "List of extracted relations"
    required :total_entities, Integer, doc: "Total entities provided for context"
    required :relations_found, Integer, doc: "Number of valid relations found"
  end
  
  # Service to extract relationships between entities using the Relation Verb Glossary
  class RelationExtractionService < OpenaiConfig::BaseExtractionService
    
    attr_reader :content, :entities, :verb_glossary
    
    def initialize(content:, entities:, verb_glossary: nil)
      @content = content
      @entities = Array(entities)
      @verb_glossary = normalize_verb_glossary(verb_glossary || Graph::EdgeLoader::VERB_GLOSSARY)
    end
    
    def call
      return empty_result if content.blank? || entities.empty?
      super
    end
    
    alias extract call
    
    protected
    
    def response_model_class
      RelationExtractionResult
    end
    
    def validate_inputs!
      raise ArgumentError, 'Content is required' if content.blank?
      raise ArgumentError, 'Entities are required' if entities.empty?
    end
    
    def content_for_extraction
      user_prompt
    end
    
    def variables_for_prompt
      {
        content: content,
        entities: entities_as_json,
        verb_glossary: verb_glossary.join(', ')
      }
    end
    
    def transform_result(parsed_result)
      # Filter relations to only include allowed verbs
      valid_relations = parsed_result.relations.select do |rel|
        verb_glossary.include?(rel.verb.to_s.downcase)
      end
      
      {
        success: true,
        relations: transform_relations(valid_relations),
        metadata: {
          total_entities: entities.size,
          relations_found: valid_relations.size,
          filtered_count: parsed_result.relations.size - valid_relations.size,
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
        You are a relationship extraction specialist for the Enliterator system.
        Your task is to extract relationships between entities using ONLY the allowed verbs.
        
        ALLOWED VERBS (use exactly as shown):
        #{format_verb_glossary}
        
        Guidelines:
        1. ONLY use verbs from the allowed list above
        2. Match entities to those provided in the entity list
        3. Include text evidence when relationship is explicit
        4. Set confidence based on clarity of relationship
        5. Focus on explicit relationships, not implied ones
        6. Respect verb directionality (source -> verb -> target)
        
        Remember: If a relationship verb is not in the allowed list, DO NOT extract it.
      PROMPT
    end
    
    def user_prompt
      <<~PROMPT
        Extract relationships from the following content using ONLY the allowed verbs.
        
        Available entities (use these for source/target):
        #{format_entities}
        
        Content to analyze:
        #{content.truncate(8000)}
        
        Return all valid relationships found using the strict verb glossary.
      PROMPT
    end
    
    def format_verb_glossary
      Graph::EdgeLoader::VERB_GLOSSARY.map do |verb, config|
        source_desc = config[:source].is_a?(Array) ? config[:source].join('/') : config[:source]
        target_desc = config[:target] == '*' ? 'any' : config[:target]
        "- #{verb}: #{source_desc} -> #{target_desc}"
      end.join("\n")
    end
    
    def format_entities
      entities.map do |entity|
        pool = entity[:pool_type] || entity['pool_type']
        label = entity[:label] || entity['label']
        id = entity[:id] || entity['id']
        "- #{pool}: #{label}#{id ? " (id: #{id})" : ''}"
      end.join("\n")
    end
    
    def entities_as_json
      entities.map do |e|
        {
          pool_type: (e[:pool_type] || e['pool_type']).to_s,
          label: e[:label] || e['label'],
          id: (e[:id] || e['id']).to_s
        }.compact
      end.to_json
    end
    
    def normalize_verb_glossary(glossary)
      if glossary.respond_to?(:keys)
        glossary.keys.map(&:to_s).map(&:downcase)
      else
        Array(glossary).map(&:to_s).map(&:downcase)
      end
    end
    
    def transform_relations(relations)
      relations.map do |rel|
        {
          source: {
            pool_type: rel.source.pool_type,
            label: rel.source.label,
            id: rel.source.id
          }.compact,
          verb: rel.verb.downcase,
          target: {
            pool_type: rel.target.pool_type,
            label: rel.target.label,
            id: rel.target.id
          }.compact,
          evidence_span: rel.evidence_span,
          confidence: rel.confidence
        }
      end
    end
    
    def empty_result
      {
        success: true,
        relations: [],
        metadata: {
          total_entities: entities.size,
          relations_found: 0,
          extraction_time: Time.current
        }.merge(extraction_metadata)
      }
    end
  end
end

