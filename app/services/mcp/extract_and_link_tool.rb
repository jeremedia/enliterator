# frozen_string_literal: true

# MCP Extract and Link Tool for Enliterator
#
# Extracts Ten Pool Canon entities from text and links them to the knowledge graph
# Uses the fine-tuned model or OpenAI for entity extraction
#
module Mcp
  class ExtractAndLinkTool
    # Ten Pool Canon categories
    POOLS = %w[Idea Practical Experience Manifest Character Time Space Lifecycle Symbolic Relator].freeze
    
    # Extract entities from text and link to knowledge graph
    # Arguments: text (string), link_threshold (float), mode (string), ekn (optional EKN object)
    # Returns: { entities: [...], linked: [...], ambiguous: [...] }
    def self.call(text:, link_threshold: 0.7, mode: 'extract', ekn: nil)
      return { error: "Text is required" } if text.blank?
      return { error: "Text too long (max 8000 chars)" } if text.length > 8000
      
      # Use provided EKN or fallback to meta-enliterator
      ekn = ekn || Ekn.find_by(slug: 'meta-enliterator') || Ekn.first
      return { error: "No EKN available" } unless ekn
      
      Rails.logger.info "MCP ExtractAndLinkTool: Processing #{text.length} chars in #{mode} mode"
      
      # Extract entities using OpenAI
      extracted = extract_entities(text)
      
      # Link to existing entities if requested
      if mode == 'link' || mode == 'extract_and_link'
        linked = link_entities(extracted, ekn, link_threshold)
        
        # Separate linked from unlinked
        ambiguous = extracted.reject { |e| linked.any? { |l| l[:extracted_name] == e[:name] } }
        
        {
          mode: mode,
          text_length: text.length,
          entities_extracted: extracted,
          entities_linked: linked,
          ambiguous_entities: ambiguous,
          summary: {
            total_extracted: extracted.size,
            successfully_linked: linked.size,
            ambiguous: ambiguous.size,
            pools_found: extracted.map { |e| e[:pool] }.uniq
          }
        }
      else
        # Just extraction, no linking
        {
          mode: mode,
          text_length: text.length,
          entities_extracted: extracted,
          summary: {
            total_extracted: extracted.size,
            pools_found: extracted.map { |e| e[:pool] }.uniq
          }
        }
      end
      
    rescue => e
      Rails.logger.error "MCP ExtractAndLinkTool error: #{e.message}"
      Rails.logger.error e.backtrace.first(10).join("\n")
      
      { error: "Extraction failed: #{e.message}" }
    end
    
    private
    
    # Extract entities using OpenAI
    def self.extract_entities(text)
      # Use structured outputs for entity extraction
      messages = [
        {
          role: "system",
          content: system_prompt
        },
        {
          role: "user",
          content: "Extract Ten Pool Canon entities from this text:\n\n#{text}"
        }
      ]
      
      # Call OpenAI with structured output
      response = OPENAI.chat.completions.create(
        model: OpenaiConfig::SettingsManager.model_for(:extraction),
        messages: messages,
        response_format: {
          type: "json_schema",
          json_schema: {
            name: "entity_extraction",
            strict: true,
            schema: extraction_schema
          }
        }
      )
      
      # Parse response
      result = JSON.parse(response.choices[0].message.content)
      
      # Format entities
      entities = []
      result["entities"].each do |entity|
        entities << {
          name: entity["name"],
          pool: entity["pool"],
          confidence: entity["confidence"],
          context: entity["context"],
          reasoning: entity["reasoning"]
        }
      end
      
      entities
      
    rescue => e
      Rails.logger.error "Entity extraction failed: #{e.message}"
      []
    end
    
    # Link extracted entities to knowledge graph
    def self.link_entities(extracted, ekn, threshold)
      linked = []
      
      extracted.each do |entity|
        # Search for matching entities
        search_tool = Mcp::Tools::SimpleSearchTool.new(ekn: ekn)
        results = search_tool.execute(
          query: entity[:name],
          top_k: 3,
          pools: [entity[:pool]]
        )
        
        if results[:items]&.any?
          # Find best match based on name similarity
          best_match = find_best_match(entity[:name], results[:items])
          
          if best_match && best_match[:score] >= threshold
            linked << {
              extracted_name: entity[:name],
              extracted_pool: entity[:pool],
              linked_entity_id: best_match[:entity][:entity_id],
              linked_entity_name: best_match[:entity][:entity_name],
              linked_entity_type: best_match[:entity][:entity_type],
              confidence: best_match[:score],
              context: entity[:context]
            }
          end
        end
      end
      
      linked
    end
    
    # Find best matching entity based on string similarity
    def self.find_best_match(name, candidates)
      return nil if candidates.empty?
      
      best = nil
      best_score = 0
      
      candidates.each do |candidate|
        # Simple string similarity (could use more sophisticated matching)
        score = string_similarity(name.downcase, candidate[:entity_name].to_s.downcase)
        
        if score > best_score
          best_score = score
          best = { entity: candidate, score: score }
        end
      end
      
      best
    end
    
    # Calculate string similarity (simple version)
    def self.string_similarity(str1, str2)
      return 0.0 if str1.empty? || str2.empty?
      
      # Exact match
      return 1.0 if str1 == str2
      
      # Contains match
      return 0.8 if str1.include?(str2) || str2.include?(str1)
      
      # Partial word match
      words1 = str1.split(/\s+/)
      words2 = str2.split(/\s+/)
      common = words1 & words2
      
      return 0.0 if common.empty?
      
      # Score based on common words
      (common.size.to_f / [words1.size, words2.size].max)
    end
    
    # System prompt for entity extraction
    def self.system_prompt
      <<~PROMPT
        You are an entity extraction specialist for the Ten Pool Canon framework.
        Extract entities that fit into these pools:
        
        - Idea: Concepts, principles, philosophies, theories
        - Practical: Methods, processes, techniques, procedures
        - Experience: Stories, testimonials, personal accounts, events
        - Manifest: Physical/digital artifacts, documents, objects
        - Character: People, agents, roles, personas
        - Time: Temporal entities, dates, periods, eras
        - Space: Locations, places, geographic entities
        - Lifecycle: States, transitions, progressions, phases
        - Symbolic: Symbols, meanings, representations, metaphors
        - Relator: Relationships, connections, associations
        
        For each entity, provide:
        1. The entity name
        2. The pool it belongs to
        3. Confidence score (0-1)
        4. Context from the text
        5. Brief reasoning for the classification
      PROMPT
    end
    
    # JSON schema for extraction
    def self.extraction_schema
      {
        type: "object",
        properties: {
          entities: {
            type: "array",
            items: {
              type: "object",
              properties: {
                name: { type: "string" },
                pool: { 
                  type: "string",
                  enum: POOLS
                },
                confidence: { 
                  type: "number",
                  minimum: 0,
                  maximum: 1
                },
                context: { type: "string" },
                reasoning: { type: "string" }
              },
              required: ["name", "pool", "confidence", "context", "reasoning"],
              additionalProperties: false
            }
          }
        },
        required: ["entities"],
        additionalProperties: false
      }
    end
  end
end