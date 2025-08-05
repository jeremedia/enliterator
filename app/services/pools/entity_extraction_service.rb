# frozen_string_literal: true

module Pools
  # Model classes for structured entity extraction
  class EntityAttributes < OpenAI::Helpers::StructuredOutput::BaseModel
    required :label, String, doc: "The name or title of the entity"
    required :abstract, String, nil?: true, doc: "A brief description or abstract (for Ideas)"
    required :principle_tags, Array, nil?: true, doc: "Principle tags (for Ideas)"
    required :components, Array, nil?: true, doc: "Component list (for Manifests)"
    required :narrative_text, String, nil?: true, doc: "Narrative content (for Experiences)"
    required :goal, String, nil?: true, doc: "The goal or purpose (for Practicals)"
    required :steps, Array, nil?: true, doc: "Steps or procedures (for Practicals)"
    required :change_note, String, nil?: true, doc: "Description of change (for Evolutionary)"
    required :influence_type, String, nil?: true, doc: "Type of influence (for Emanations)"
    required :relation_type, String, nil?: true, doc: "Type of relation (for Relational)"
    required :time_reference, String, nil?: true, doc: "Temporal reference extracted from text"
  end

  class ExtractedEntity < OpenAI::Helpers::StructuredOutput::BaseModel
    required :pool_type, String, doc: "Pool type: idea, manifest, experience, relational, evolutionary, practical, emanation"
    required :confidence, Float, doc: "Extraction confidence (0-1)"
    required :attributes, EntityAttributes, doc: "Pool-specific attributes"
    required :lexicon_match, String, nil?: true, doc: "Matched canonical term from lexicon"
    required :source_span, String, doc: "Text span this entity was extracted from"
  end

  class EntityExtractionResult < OpenAI::Helpers::StructuredOutput::BaseModel
    required :entities, Array, doc: "List of extracted entities"
    required :extraction_metadata, Hash, doc: "Metadata about the extraction"
  end

  # Service to extract entities for the Ten Pool Canon using OpenAI Responses API
  class EntityExtractionService < ApplicationService
    
    POOL_DESCRIPTIONS = {
      'idea' => 'Purpose: capture the why (principles, theories, intents, design rationales). Look for principles, doctrines, hypotheses, themes.',
      'manifest' => 'Purpose: capture the what (concrete instances and artifacts). Look for projects, items, laws, artworks, releases.',
      'experience' => 'Purpose: capture lived outcomes and perception. Look for testimonials, observations, stories, reviews.',
      'relational' => 'Purpose: capture connections, lineages, and networks. Look for collaborations, precedents, citations, membership edges.',
      'evolutionary' => 'Purpose: capture change over time. Look for timelines, versions, forks, status changes.',
      'practical' => 'Purpose: capture how-to and tacit knowledge. Look for guides, SOPs, checklists, recipes, playbooks.',
      'emanation' => 'Purpose: capture ripple effects and downstream influence. Look for adoptions, remixes, movements, policies.'
    }.freeze

    attr_reader :content, :lexicon_context, :source_metadata

    def initialize(content:, lexicon_context: [], source_metadata: {})
      @content = content
      @lexicon_context = lexicon_context
      @source_metadata = source_metadata
    end

    def extract
      return { success: false, error: 'Content is blank' } if content.blank?

      # Build the extraction prompt
      input_messages = build_input

      # Call OpenAI with Responses API
      response = OPENAI.responses.create(
        model: ENV.fetch('OPENAI_MODEL', 'gpt-4o-2024-08-06'),
        input: input_messages,
        text: EntityExtractionResult,
        temperature: 0  # Deterministic extraction
      )

      # Process the structured response
      result = response.output
        .flat_map { |output| output.content }
        .grep_v(OpenAI::Models::Responses::ResponseOutputRefusal)
        .first

      if result
        extraction = result.parsed
        
        # Transform to our internal format
        entities = transform_entities(extraction.entities)
        
        {
          success: true,
          entities: entities,
          metadata: extraction.extraction_metadata
        }
      else
        { success: false, error: 'No valid response from OpenAI' }
      end
    rescue StandardError => e
      Rails.logger.error "Entity extraction failed: #{e.message}"
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
        You are an entity extraction specialist for the Enliterator system.
        Your task is to extract entities that belong to the Ten Pool Canon.
        
        Pool Descriptions:
        #{POOL_DESCRIPTIONS.map { |pool, desc| "- #{pool.upcase}: #{desc}" }.join("\n")}
        
        Guidelines:
        1. Extract clear, distinct entities that fit into one of the pools
        2. Prefer canonical terms from the lexicon when available
        3. Include time references when mentioned
        4. Set confidence based on clarity and context
        5. Each entity should have pool-appropriate attributes
        6. Do not duplicate entities - merge similar references
        
        Lexicon Context (canonical terms to prefer):
        #{format_lexicon_context}
      PROMPT
    end

    def user_prompt
      <<~PROMPT
        Extract entities from the following content for the Ten Pool Canon.
        Focus on clear, well-defined entities that can be nodes in a knowledge graph.
        
        Content:
        #{content.truncate(8000)}
        
        Source metadata: #{source_metadata.to_json}
      PROMPT
    end

    def format_lexicon_context
      return "None available" if lexicon_context.empty?
      
      lexicon_context.map do |term, pool, description|
        "- #{term} (#{pool}): #{description}"
      end.join("\n")
    end

    def transform_entities(entities)
      entities.map do |entity|
        {
          pool_type: entity.pool_type,
          confidence: entity.confidence,
          attributes: build_attributes(entity.pool_type, entity.attributes),
          lexicon_match: entity.lexicon_match,
          source_span: entity.source_span
        }
      end
    end

    def build_attributes(pool_type, attrs)
      # Start with common attributes
      base_attrs = {
        label: attrs.label,
        repr_text: generate_repr_text(pool_type, attrs)
      }

      # Add time field based on content
      if attrs.time_reference.present?
        base_attrs[:valid_time_start] = parse_time_reference(attrs.time_reference)
      else
        base_attrs[:valid_time_start] = Time.current
      end

      # Add pool-specific attributes
      case pool_type
      when 'idea'
        base_attrs.merge(
          abstract: attrs.abstract || "Extracted concept: #{attrs.label}",
          principle_tags: attrs.principle_tags || [],
          inception_date: base_attrs[:valid_time_start]
        )
      when 'manifest'
        base_attrs.merge(
          manifest_type: detect_manifest_type(attrs),
          components: attrs.components || [],
          time_bounds: { start: base_attrs[:valid_time_start], end: nil }
        )
      when 'experience'
        base_attrs.merge(
          agent_label: extract_agent_label(attrs),
          context: source_metadata[:context] || 'general',
          narrative_text: attrs.narrative_text || attrs.label,
          sentiment: detect_sentiment(attrs.narrative_text),
          observed_at: base_attrs[:valid_time_start]
        )
      when 'practical'
        base_attrs.merge(
          goal: attrs.goal || "How to: #{attrs.label}",
          steps: attrs.steps || [],
          prerequisites: [],
          hazards: []
        )
      when 'evolutionary'
        base_attrs.merge(
          change_note: attrs.change_note || "Evolution of #{attrs.label}",
          version_id: generate_version_id
        )
      when 'emanation'
        base_attrs.merge(
          influence_type: attrs.influence_type || 'general',
          target_context: source_metadata[:context] || 'unknown',
          pathway: 'extracted'
        )
      when 'relational'
        base_attrs.merge(
          relation_type: attrs.relation_type || 'connection',
          strength: 0.7 # Default strength
        )
      else
        base_attrs
      end
    end

    def generate_repr_text(pool_type, attrs)
      case pool_type
      when 'idea'
        "#{attrs.label} (principle)"
      when 'manifest'
        "#{attrs.label} (artifact)"
      when 'experience'
        "#{attrs.label} (lived)"
      when 'practical'
        "#{attrs.label} (how-to)"
      else
        attrs.label
      end
    end

    def parse_time_reference(time_ref)
      # Simple time parsing - could be enhanced
      case time_ref
      when /(\d{4})/
        Date.new($1.to_i, 1, 1)
      when /today|current|now/i
        Time.current
      when /yesterday/i
        1.day.ago
      else
        Time.current
      end
    rescue
      Time.current
    end

    def detect_manifest_type(attrs)
      label_lower = attrs.label.downcase
      case label_lower
      when /project|installation|build/
        'project'
      when /art|sculpture|piece/
        'artwork'
      when /event|gathering|ceremony/
        'event'
      when /document|guide|manual/
        'document'
      else
        'general'
      end
    end

    def extract_agent_label(attrs)
      # Try to extract who reported the experience
      if attrs.narrative_text =~ /^(\w+)\s+said|reported|observed/i
        $1
      else
        'Anonymous'
      end
    end

    def detect_sentiment(text)
      return 'neutral' if text.blank?
      
      positive_words = %w[amazing wonderful great fantastic love beautiful incredible]
      negative_words = %w[terrible awful bad horrible hate ugly disappointing]
      
      text_lower = text.downcase
      positive_count = positive_words.count { |w| text_lower.include?(w) }
      negative_count = negative_words.count { |w| text_lower.include?(w) }
      
      if positive_count > negative_count
        'positive'
      elsif negative_count > positive_count
        'negative'
      else
        'neutral'
      end
    end

    def generate_version_id
      "v#{Time.current.strftime('%Y%m%d%H%M%S')}"
    end
  end
end