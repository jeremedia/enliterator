# frozen_string_literal: true

# Enhanced MCP Extract and Link Tool with Multi-Pass Strategy
#
# Addresses key issues:
# 1. Context-aware classification (same entity can be different pools)
# 2. Multi-pass extraction for better accuracy
# 3. Pool-specific validation and quality checks
# 4. Enhanced prompts with detailed examples and edge cases
#
module Mcp
  class EnhancedExtractAndLinkTool
    # Ten Pool Canon categories
    POOLS = %w[Idea Practical Experience Manifest Character Time Space Lifecycle Symbolic Relator].freeze
    
    # Expected pool distribution for validation (rough guidelines)
    EXPECTED_POOL_USAGE = {
      min_pools_used: 5,  # Should use at least 5 different pools
      max_single_pool_dominance: 0.7,  # No single pool should have >70% of entities
      required_pools: %w[Character Space Time] # These should almost always appear
    }.freeze
    
    # Multi-pass extraction with validation and refinement
    def self.call(text:, link_threshold: 0.7, mode: 'extract', ekn: nil)
      return { error: "Text is required" } if text.blank?
      # Use appropriate context window limits based on model selection
      # gpt-5-mini-2025-08-07: 400K context (400,000 chars)  
      # gpt-4.1-2025-04-14: 1M context (1,047,576 chars)
      return { error: "Text too long (max 1M chars)" } if text.length > 1_047_576
      
      # Use provided EKN or fallback to meta-enliterator
      ekn = ekn || Ekn.find_by(slug: 'meta-enliterator') || Ekn.first
      return { error: "No EKN available" } unless ekn
      
      Rails.logger.info "Enhanced ExtractAndLinkTool: Multi-pass processing #{text.length} chars"
      
      # PASS 1: Initial broad extraction
      initial_entities = extract_entities_pass_one(text)
      
      # PASS 2: Context-aware refinement and validation
      refined_entities = refine_entities_pass_two(text, initial_entities)
      
      # PASS 3: Missing pool detection and targeted extraction
      final_entities = detect_and_extract_missing_pools(text, refined_entities)
      
      # PASS 4: Final validation and quality checks
      validated_entities = validate_and_clean_entities(final_entities, text)
      
      # Generate quality report
      quality_report = generate_quality_report(validated_entities, text)
      
      # Link to existing entities if requested
      if mode == 'link' || mode == 'extract_and_link'
        linked = link_entities(validated_entities, ekn, link_threshold)
        ambiguous = validated_entities.reject { |e| linked.any? { |l| l[:extracted_name] == e[:name] } }
        
        {
          mode: mode,
          text_length: text.length,
          extraction_strategy: 'multi_pass_enhanced',
          entities_extracted: validated_entities,
          entities_linked: linked,
          ambiguous_entities: ambiguous,
          quality_report: quality_report,
          summary: {
            total_extracted: validated_entities.size,
            successfully_linked: linked.size,
            ambiguous: ambiguous.size,
            pools_found: validated_entities.map { |e| e[:pool] }.uniq,
            quality_score: quality_report[:overall_quality_score]
          }
        }
      else
        {
          mode: mode,
          text_length: text.length,
          extraction_strategy: 'multi_pass_enhanced',
          entities_extracted: validated_entities,
          quality_report: quality_report,
          summary: {
            total_extracted: validated_entities.size,
            pools_found: validated_entities.map { |e| e[:pool] }.uniq,
            quality_score: quality_report[:overall_quality_score]
          }
        }
      end
      
    rescue => e
      Rails.logger.error "Enhanced ExtractAndLinkTool error: #{e.message}"
      Rails.logger.error e.backtrace.first(10).join("\n")
      
      { error: "Enhanced extraction failed: #{e.message}" }
    end
    
    private
    
    # PASS 1: Initial broad extraction with enhanced prompt
    def self.extract_entities_pass_one(text)
      Rails.logger.info "Pass 1: Initial broad extraction"
      
      messages = [
        {
          role: "system",
          content: enhanced_system_prompt_pass_one
        },
        {
          role: "user",
          content: "Extract Ten Pool Canon entities from this text:\n\n#{text}"
        }
      ]
      
      response = OPENAI.chat.completions.create(
        model: OpenaiConfig::SettingsManager.model_for(:extraction, content_length: text.length),
        messages: messages,
        response_format: {
          type: "json_schema",
          json_schema: {
            name: "entity_extraction_pass_one",
            strict: true,
            schema: enhanced_extraction_schema
          }
        }
      )
      
      result = JSON.parse(response.choices[0].message.content)
      format_entities(result["entities"])
      
    rescue => e
      Rails.logger.error "Pass 1 extraction failed: #{e.message}"
      []
    end
    
    # PASS 2: Context-aware refinement
    def self.refine_entities_pass_two(text, entities)
      Rails.logger.info "Pass 2: Context-aware refinement"
      return entities if entities.empty?
      
      # Focus on problematic classifications
      refinement_prompt = build_refinement_prompt(text, entities)
      
      messages = [
        {
          role: "system", 
          content: enhanced_system_prompt_pass_two
        },
        {
          role: "user",
          content: refinement_prompt
        }
      ]
      
      response = OPENAI.chat.completions.create(
        model: OpenaiConfig::SettingsManager.model_for(:extraction, content_length: text.length),
        messages: messages,
        response_format: {
          type: "json_schema",
          json_schema: {
            name: "entity_refinement",
            strict: true,
            schema: refinement_schema
          }
        }
      )
      
      result = JSON.parse(response.choices[0].message.content)
      apply_refinements(entities, result["refinements"])
      
    rescue => e
      Rails.logger.error "Pass 2 refinement failed: #{e.message}"
      entities
    end
    
    # PASS 3: Missing pool detection and targeted extraction  
    def self.detect_and_extract_missing_pools(text, entities)
      Rails.logger.info "Pass 3: Missing pool detection"
      
      used_pools = entities.map { |e| e[:pool] }.uniq
      missing_pools = POOLS - used_pools
      
      return entities if missing_pools.empty?
      
      # Targeted extraction for missing pools
      targeted_entities = extract_missing_pool_entities(text, missing_pools)
      
      entities + targeted_entities
    end
    
    # PASS 4: Final validation and quality checks
    def self.validate_and_clean_entities(entities, text)
      Rails.logger.info "Pass 4: Validation and quality checks"
      
      # Remove duplicates and low-confidence entities
      cleaned = entities.uniq { |e| e[:name].downcase.strip }
                      .select { |e| e[:confidence] >= 0.3 }
      
      # Validate pool distribution
      if needs_redistribution?(cleaned)
        cleaned = rebalance_pool_distribution(cleaned, text)
      end
      
      cleaned
    end
    
    # Enhanced system prompt for Pass 1 - comprehensive with examples
    def self.enhanced_system_prompt_pass_one
      <<~PROMPT
        You are an expert entity extraction specialist for the Ten Pool Canon framework. Your task is comprehensive entity extraction with careful attention to context and pool classification.

        ## THE TEN POOL CANON - DETAILED DEFINITIONS:

        ### 1. IDEA 🧠
        **Abstract concepts, principles, theories, philosophies, frameworks**
        - Examples: "Climate Change Theory", "Sustainability", "Resilience Framework", "Adaptive Management"
        - Look for: Conceptual frameworks, scientific principles, philosophical ideas, theoretical models
        - NOT physical things or specific methods

        ### 2. PRACTICAL 🔧  
        **Methods, processes, techniques, procedures, how-to knowledge**
        - Examples: "Ice Core Drilling Method", "Community Engagement Process", "Data Collection Protocol"
        - Look for: Step-by-step processes, methodologies, techniques, procedures
        - Includes "how to" instructions and operational methods

        ### 3. EXPERIENCE 🌟
        **Personal accounts, stories, events, testimonials, case studies**  
        - Examples: "2019 Arctic Expedition", "Community Workshop in Utqiagvik", "Researcher Field Experience"
        - Look for: Specific events, personal narratives, case studies, lived experiences
        - Include both positive and negative experiences

        ### 4. MANIFEST 🏗️
        **Physical/digital artifacts, documents, objects, concrete implementations**
        - Examples: "Temperature Sensor Array", "Research Station", "Policy Document", "Database System"
        - Look for: Physical objects, documents, artifacts, concrete implementations
        - NOT institutions acting as agents (see Character)

        ### 5. CHARACTER 👤
        **People, roles, agents, personas - entities that ACT**
        - Examples: "Dr. Sarah Johnson", "Arctic Researchers", "Community Elders", "Policy Makers"  
        - Look for: Individual names, human roles, groups acting as agents, personas
        - CRITICAL: Institutions acting as agents ("NASA decided", "University concluded")
        - NOT just mentioned institutions (see Manifest)

        ### 6. TIME ⏰
        **Temporal entities, periods, chronologies, schedules**
        - Examples: "Arctic Summer Season", "Pre-Industrial Period", "2015-2020", "Daily Monitoring Schedule"
        - Look for: Time periods, dates, seasons, temporal patterns, schedules
        - Include both specific times and temporal concepts

        ### 7. SPACE 🗺️
        **Locations, places, geographic entities, spatial relationships**
        - Examples: "Beaufort Sea", "North Slope Borough", "Arctic Research Station Location"
        - Look for: Geographic locations, spatial relationships, areas, regions
        - Include both physical and conceptual spaces

        ### 8. LIFECYCLE 🔄
        **Stages, phases, processes, transitions, developmental sequences**
        - Examples: "Ice Formation Cycle", "Research Project Phases", "Community Development Stages"
        - Look for: Process stages, developmental phases, cyclical patterns
        - Focused on progression and change over time

        ### 9. SYMBOLIC 🔮
        **Symbols, meanings, metaphors, cultural significance, representations**
        - Examples: "Polar Bear as Climate Symbol", "Ice as Cultural Memory", "Sacred Hunting Grounds"
        - Look for: Metaphorical meanings, cultural symbols, abstract representations
        - Things that represent deeper meanings beyond literal interpretation

        ### 10. RELATOR 🔗
        **Relationships, connections, dependencies, associations between entities**
        - Examples: "Climate-Community Relationship", "Research Partnership", "Cause-Effect Connection"
        - Look for: Explicit relationships, dependencies, correlations, partnerships
        - Focus on the connection itself, not the connected entities

        ## CRITICAL CLASSIFICATION RULES:

        ### Context Matters:
        - "Harvard University" could be:
          * CHARACTER: "Harvard University concluded that..." (acting as agent)
          * MANIFEST: "Harvard's research facility" (physical building/document)
          * SPACE: "Located at Harvard University" (geographic reference)

        ### People vs Institutions:
        - CHARACTER: Individual people, roles, groups acting with agency
        - MANIFEST: Institutional artifacts, documents, systems
        - Look for action verbs and agency indicators

        ### Process vs Product:
        - PRACTICAL: The method/process itself ("drilling technique")  
        - MANIFEST: The physical result ("the ice core sample")
        - LIFECYCLE: The stages of development ("sample analysis phases")

        ## EXTRACTION STRATEGY:
        1. Read the entire text for context
        2. Identify entities and their roles in sentences
        3. Consider document type (academic, government, personal)
        4. Classify based on function, not just category
        5. Aim for balanced distribution across pools
        6. Provide detailed reasoning for edge cases

        Extract entities comprehensively, ensuring all 10 pools are considered.
      PROMPT
    end
    
    # Enhanced system prompt for Pass 2 - refinement focus
    def self.enhanced_system_prompt_pass_two
      <<~PROMPT
        You are refining entity classifications based on deeper contextual analysis. Focus on common misclassification patterns:

        ## COMMON MISCLASSIFICATION FIXES:

        ### 1. Institutions as Characters vs Manifests:
        - CHARACTER: When institution acts as agent ("University decided", "Agency implemented")  
        - MANIFEST: When referring to physical/documentary aspects ("University building", "Agency report")

        ### 2. Missing Human Elements:
        - Look harder for individual people, roles, research teams
        - "Principal Investigator", "Research Team", "Community Members" are Characters
        - Authors, researchers, policy makers often mentioned but missed

        ### 3. Temporal and Spatial Entities:
        - TIME: "during winter", "2019 season", "over the past decade"
        - SPACE: "northern Alaska", "research site", "coastal regions"

        ### 4. Relationship Extraction:
        - RELATOR: "correlation between", "impact of", "relationship with"
        - Often appear as connecting phrases between entities

        ### 5. Symbolic and Lifecycle Missing:
        - SYMBOLIC: Cultural meanings, metaphorical uses, symbolic representations
        - LIFECYCLE: Stages, phases, developmental processes

        Review each entity and refine classification based on sentence context and grammatical role.
      PROMPT
    end
    
    # Build refinement prompt with specific entities to review
    def self.build_refinement_prompt(text, entities)
      pool_distribution = entities.group_by { |e| e[:pool] }.transform_values(&:count)
      
      <<~PROMPT
        Original text: #{text[0..1000]}#{'...' if text.length > 1000}
        
        Current entities extracted: #{entities.size}
        Pool distribution: #{pool_distribution}
        
        Issues to address:
        #{"- Only #{pool_distribution.keys.count}/10 pools used - look for missing pools" if pool_distribution.keys.count < 5}
        #{"- Too many Manifests (#{pool_distribution['Manifest']}), check for misclassified Characters" if pool_distribution['Manifest'].to_i > entities.size * 0.5}
        #{"- No Characters found - look for people, researchers, organizations acting as agents" if pool_distribution['Character'].to_i == 0}
        #{"- No Time entities - look for temporal references" if pool_distribution['Time'].to_i == 0}
        #{"- No Space entities - look for geographic locations" if pool_distribution['Space'].to_i == 0}
        
        Review these specific entities for potential reclassification:
        #{entities.select { |e| needs_review?(e, pool_distribution) }.first(10).map { |e| "- #{e[:name]} (#{e[:pool]}): #{e[:reasoning]}" }.join("\n")}
        
        Provide refinement suggestions with detailed reasoning.
      PROMPT
    end
    
    # Determine if an entity needs review
    def self.needs_review?(entity, distribution)
      # Review Manifests that might be Characters
      return true if entity[:pool] == 'Manifest' && might_be_character?(entity[:name])
      
      # Review high-confidence entities in over-represented pools  
      over_represented = distribution.select { |_, count| count > distribution.values.sum * 0.4 }.keys
      return true if over_represented.include?(entity[:pool]) && entity[:confidence] > 0.8
      
      false
    end
    
    # Check if a manifest might actually be a character
    def self.might_be_character?(name)
      character_indicators = %w[university college institute organization committee department team group researchers authors scientists community members staff personnel]
      character_indicators.any? { |indicator| name.downcase.include?(indicator) }
    end
    
    # Extract entities for missing pools with targeted prompts
    def self.extract_missing_pool_entities(text, missing_pools)
      return [] if missing_pools.empty?
      
      targeted_prompt = build_targeted_extraction_prompt(text, missing_pools)
      
      messages = [
        {
          role: "system",
          content: "You are extracting entities specifically for missing pools. Focus only on the requested pool types."
        },
        {
          role: "user", 
          content: targeted_prompt
        }
      ]
      
      response = OPENAI.chat.completions.create(
        model: OpenaiConfig::SettingsManager.model_for(:extraction, content_length: text.length),
        messages: messages,
        response_format: {
          type: "json_schema",
          json_schema: {
            name: "targeted_extraction",
            strict: true,
            schema: enhanced_extraction_schema
          }
        }
      )
      
      result = JSON.parse(response.choices[0].message.content)
      format_entities(result["entities"])
      
    rescue => e
      Rails.logger.error "Targeted extraction failed: #{e.message}"
      []
    end
    
    # Build targeted extraction prompt for missing pools
    def self.build_targeted_extraction_prompt(text, missing_pools)
      pool_instructions = missing_pools.map do |pool|
        case pool
        when 'Character'
          "- CHARACTER: Look for individual names, research teams, organizations ACTING as agents, roles like 'researchers', 'community members'"
        when 'Time'  
          "- TIME: Look for temporal references like seasons, years, periods, 'during', 'since', 'over time'"
        when 'Space'
          "- SPACE: Look for geographic locations, regions, sites, 'in Alaska', 'northern regions', research locations"
        when 'Lifecycle'
          "- LIFECYCLE: Look for stages, phases, development processes, cycles, transitions"
        when 'Symbolic'
          "- SYMBOLIC: Look for metaphorical meanings, cultural symbols, representations"
        when 'Relator'
          "- RELATOR: Look for relationships, correlations, connections, 'relationship between', 'impact of'"
        else
          "- #{pool}: Extract entities for this pool type"
        end
      end.join("\n")
      
      <<~PROMPT
        Focus ONLY on extracting entities for these missing pools:
        #{pool_instructions}
        
        Text to analyze:
        #{text}
        
        Extract entities ONLY for the missing pools listed above. Be thorough and look carefully.
      PROMPT
    end
    
    # Format entities to consistent structure
    def self.format_entities(raw_entities)
      raw_entities.map do |entity|
        {
          name: entity["name"],
          pool: entity["pool"],
          confidence: entity["confidence"],
          context: entity["context"],
          reasoning: entity["reasoning"]
        }
      end
    end
    
    # Apply refinements from Pass 2
    def self.apply_refinements(entities, refinements)
      refinements.each do |refinement|
        entity = entities.find { |e| e[:name] == refinement["entity_name"] }
        next unless entity
        
        if refinement["new_pool"] != entity[:pool]
          Rails.logger.info "Refining #{entity[:name]}: #{entity[:pool]} -> #{refinement['new_pool']}"
          entity[:pool] = refinement["new_pool"]
          entity[:reasoning] = refinement["reasoning"]
          entity[:confidence] = [entity[:confidence] + 0.1, 1.0].min
        end
      end
      
      entities
    end
    
    # Check if entities need redistribution
    def self.needs_redistribution?(entities)
      pool_counts = entities.group_by { |e| e[:pool] }.transform_values(&:count)
      
      # Check minimum pools used
      return true if pool_counts.keys.count < EXPECTED_POOL_USAGE[:min_pools_used]
      
      # Check for single pool dominance
      max_pool_ratio = pool_counts.values.max.to_f / entities.count
      return true if max_pool_ratio > EXPECTED_POOL_USAGE[:max_single_pool_dominance]
      
      # Check for missing required pools
      missing_required = EXPECTED_POOL_USAGE[:required_pools] - pool_counts.keys
      return true if missing_required.any?
      
      false
    end
    
    # Rebalance pool distribution if needed
    def self.rebalance_pool_distribution(entities, text)
      Rails.logger.info "Rebalancing pool distribution"
      
      # For now, just return entities - could implement sophisticated rebalancing
      entities
    end
    
    # Generate quality report
    def self.generate_quality_report(entities, text)
      pool_counts = entities.group_by { |e| e[:pool] }.transform_values(&:count)
      
      {
        total_entities: entities.count,
        pools_used: pool_counts.keys.count,
        pool_distribution: pool_counts,
        avg_confidence: entities.map { |e| e[:confidence] }.sum / entities.count.to_f,
        quality_issues: assess_quality_issues(entities, pool_counts),
        overall_quality_score: calculate_quality_score(entities, pool_counts)
      }
    end
    
    # Assess quality issues
    def self.assess_quality_issues(entities, pool_counts)
      issues = []
      
      issues << "Only #{pool_counts.keys.count}/10 pools used" if pool_counts.keys.count < 6
      issues << "No Characters found - check for people/agents" if pool_counts['Character'].to_i == 0
      issues << "No Time entities found" if pool_counts['Time'].to_i == 0  
      issues << "No Space entities found" if pool_counts['Space'].to_i == 0
      issues << "Manifest pool over-represented (#{pool_counts['Manifest']} entities)" if pool_counts['Manifest'].to_i > entities.count * 0.6
      
      avg_confidence = entities.map { |e| e[:confidence] }.sum / entities.count.to_f
      issues << "Low average confidence (#{avg_confidence.round(2)})" if avg_confidence < 0.6
      
      issues
    end
    
    # Calculate overall quality score (0-1)
    def self.calculate_quality_score(entities, pool_counts)
      return 0.0 if entities.empty?
      
      # Pool diversity score (0-0.4)
      pool_diversity = (pool_counts.keys.count / 10.0) * 0.4
      
      # Confidence score (0-0.3)
      avg_confidence = entities.map { |e| e[:confidence] }.sum / entities.count.to_f
      confidence_score = avg_confidence * 0.3
      
      # Distribution balance score (0-0.3)
      max_pool_ratio = pool_counts.values.max.to_f / entities.count
      balance_score = (1 - max_pool_ratio).clamp(0, 1) * 0.3
      
      (pool_diversity + confidence_score + balance_score).round(2)
    end
    
    # Enhanced extraction schema
    def self.enhanced_extraction_schema
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
    
    # Refinement schema for Pass 2
    def self.refinement_schema
      {
        type: "object",
        properties: {
          refinements: {
            type: "array",
            items: {
              type: "object",
              properties: {
                entity_name: { type: "string" },
                new_pool: { 
                  type: "string", 
                  enum: POOLS
                },
                reasoning: { type: "string" }
              },
              required: ["entity_name", "new_pool", "reasoning"],
              additionalProperties: false
            }
          }
        },
        required: ["refinements"],
        additionalProperties: false
      }
    end
    
    # Link extracted entities to knowledge graph (reuse from original)
    def self.link_entities(extracted, ekn, threshold)
      # Reuse linking logic from original ExtractAndLinkTool
      ExtractAndLinkTool.send(:link_entities, extracted, ekn, threshold)
    end
  end
end