# frozen_string_literal: true

# MCP Analyze Pools Tool for Enliterator
#
# Analyzes text to identify which Ten Pool Canon categories are present
# Provides a distribution analysis and key entities per pool
#
module Mcp
  class AnalyzePoolsTool
    # Ten Pool Canon with descriptions
    POOL_DEFINITIONS = {
      'Idea' => 'Concepts, principles, philosophies, theories, abstract thoughts',
      'Practical' => 'Methods, processes, techniques, procedures, how-to knowledge',
      'Experience' => 'Stories, testimonials, personal accounts, lived events',
      'Manifest' => 'Physical/digital artifacts, documents, tangible objects',
      'Character' => 'People, agents, roles, personas, individual actors',
      'Time' => 'Temporal entities, dates, periods, eras, chronological markers',
      'Space' => 'Locations, places, geographic entities, spatial references',
      'Lifecycle' => 'States, transitions, progressions, phases, evolution',
      'Symbolic' => 'Symbols, meanings, representations, metaphors, allegories',
      'Relator' => 'Relationships, connections, associations, links between entities'
    }.freeze
    
    # Analyze text for Ten Pool Canon distribution
    # Arguments: text (string), include_entities (boolean)
    # Returns: { pools: {...}, entities: [...], analysis: {...} }
    def self.call(text:, include_entities: true)
      return { error: "Text is required" } if text.blank?
      return { error: "Text too long (max 8000 chars)" } if text.length > 8000
      
      Rails.logger.info "MCP AnalyzePoolsTool: Analyzing #{text.length} chars"
      
      # Analyze the text
      analysis = analyze_text(text, include_entities)
      
      # Calculate statistics
      stats = calculate_statistics(analysis)
      
      # Build response
      {
        text_length: text.length,
        pools: analysis[:pools],
        dominant_pool: stats[:dominant_pool],
        distribution: stats[:distribution],
        entities: include_entities ? analysis[:entities] : nil,
        analysis: {
          total_signals: stats[:total_signals],
          pool_diversity: stats[:diversity],
          confidence: stats[:confidence],
          summary: generate_summary(analysis, stats)
        }
      }
      
    rescue => e
      Rails.logger.error "MCP AnalyzePoolsTool error: #{e.message}"
      Rails.logger.error e.backtrace.first(10).join("\n")
      
      { error: "Analysis failed: #{e.message}" }
    end
    
    private
    
    # Analyze text using OpenAI
    def self.analyze_text(text, include_entities)
      messages = [
        {
          role: "system",
          content: system_prompt
        },
        {
          role: "user",
          content: "Analyze this text for Ten Pool Canon categories:\n\n#{text}"
        }
      ]
      
      # Call OpenAI with structured output
      response = OPENAI.chat.completions.create(
        model: OpenaiConfig::SettingsManager.model_for(:analysis),
        messages: messages,
        response_format: {
          type: "json_schema",
          json_schema: {
            name: "pool_analysis",
            strict: true,
            schema: analysis_schema(include_entities)
          }
        }
      )
      
      # Parse response
      result = JSON.parse(response.choices[0].message.content)
      
      # Format pools analysis
      pools = {}
      result["pools"].each do |pool|
        pools[pool["name"]] = {
          score: pool["score"],
          confidence: pool["confidence"],
          indicators: pool["indicators"],
          example_phrases: pool["example_phrases"]
        }
      end
      
      # Format entities if included
      entities = []
      if include_entities && result["entities"]
        result["entities"].each do |entity|
          entities << {
            name: entity["name"],
            pool: entity["pool"],
            relevance: entity["relevance"]
          }
        end
      end
      
      {
        pools: pools,
        entities: entities,
        overall_assessment: result["overall_assessment"]
      }
      
    rescue => e
      Rails.logger.error "Text analysis failed: #{e.message}"
      { pools: {}, entities: [], overall_assessment: "Analysis failed" }
    end
    
    # Calculate statistics from analysis
    def self.calculate_statistics(analysis)
      pools = analysis[:pools]
      
      # Find dominant pool
      dominant = pools.max_by { |_name, data| data[:score] }
      
      # Calculate total signals
      total_signals = pools.values.sum { |p| p[:score] }
      
      # Calculate distribution percentages
      distribution = {}
      pools.each do |name, data|
        distribution[name] = total_signals > 0 ? (data[:score] / total_signals.to_f * 100).round(1) : 0
      end
      
      # Calculate diversity (0-1, higher is more diverse)
      active_pools = pools.select { |_name, data| data[:score] > 0 }.size
      diversity = active_pools.to_f / POOL_DEFINITIONS.size
      
      # Average confidence
      confidence = pools.values.map { |p| p[:confidence] }.sum / pools.size.to_f
      
      {
        dominant_pool: dominant ? dominant[0] : nil,
        distribution: distribution,
        total_signals: total_signals,
        diversity: diversity.round(2),
        confidence: confidence.round(2)
      }
    end
    
    # Generate human-readable summary
    def self.generate_summary(analysis, stats)
      parts = []
      
      # Dominant pool
      if stats[:dominant_pool]
        parts << "The text is primarily #{stats[:dominant_pool]}-oriented (#{stats[:distribution][stats[:dominant_pool]]}%)"
      end
      
      # Diversity
      if stats[:diversity] > 0.7
        parts << "Shows high diversity across multiple pools"
      elsif stats[:diversity] > 0.4
        parts << "Moderate pool diversity"
      else
        parts << "Focused on a few specific pools"
      end
      
      # Key entities
      if analysis[:entities]&.any?
        top_entities = analysis[:entities].first(3).map { |e| e[:name] }
        parts << "Key entities: #{top_entities.join(', ')}"
      end
      
      # Overall assessment
      if analysis[:overall_assessment]
        parts << analysis[:overall_assessment]
      end
      
      parts.join(". ")
    end
    
    # System prompt for pool analysis
    def self.system_prompt
      <<~PROMPT
        You are a Ten Pool Canon analyst. Analyze text to identify which pools are represented.
        
        The Ten Pools are:
        #{POOL_DEFINITIONS.map { |name, desc| "- #{name}: #{desc}" }.join("\n")}
        
        For each pool present in the text:
        1. Score its presence (0-10)
        2. Confidence in the assessment (0-1)
        3. Key indicators (words/phrases that signal this pool)
        4. Example phrases from the text
        
        Also identify key entities if requested, classifying each by its primary pool.
        
        Provide an overall assessment of the text's pool distribution.
      PROMPT
    end
    
    # JSON schema for analysis
    def self.analysis_schema(include_entities)
      schema = {
        type: "object",
        properties: {
          pools: {
            type: "array",
            items: {
              type: "object",
              properties: {
                name: {
                  type: "string",
                  enum: POOL_DEFINITIONS.keys
                },
                score: {
                  type: "integer",
                  minimum: 0,
                  maximum: 10
                },
                confidence: {
                  type: "number",
                  minimum: 0,
                  maximum: 1
                },
                indicators: {
                  type: "array",
                  items: { type: "string" }
                },
                example_phrases: {
                  type: "array",
                  items: { type: "string" }
                }
              },
              required: ["name", "score", "confidence", "indicators", "example_phrases"],
              additionalProperties: false
            }
          },
          overall_assessment: { type: "string" }
        },
        required: ["pools", "overall_assessment"],
        additionalProperties: false
      }
      
      # Add entities if requested
      if include_entities
        schema[:properties][:entities] = {
          type: "array",
          items: {
            type: "object",
            properties: {
              name: { type: "string" },
              pool: {
                type: "string",
                enum: POOL_DEFINITIONS.keys
              },
              relevance: {
                type: "number",
                minimum: 0,
                maximum: 1
              }
            },
            required: ["name", "pool", "relevance"],
            additionalProperties: false
          }
        }
        schema[:required] << "entities"
      end
      
      schema
    end
  end
end