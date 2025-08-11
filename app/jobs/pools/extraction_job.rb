# frozen_string_literal: true

# PURPOSE: Stage 4 of the 9-stage pipeline - Pool Filling (Entity Extraction Only)
#
# CRITICAL DESIGN DECISION:
# Relationships are NOT extracted at this stage. Here's why:
#
# 1. Limited Context: At item level, we only see ~7 entities from a single file.
#    Real relationships exist ACROSS items (e.g., ControllerClass uses ModelClass).
#
# 2. Wrong Timing: We need all entities in the graph first to discover meaningful
#    cross-cutting relationships. Extracting within items creates disconnected islands.
#
# 3. Token Waste: Sending unrelated entities wastes tokens and finds nothing useful.
#
# Relationships are discovered in Stage 5.5 (Graph::RelationshipDiscoveryJob) after
# all entities are loaded, using clustering to find related entity groups.
#
# See docs/ISSUE_RELATIONSHIP_EXTRACTION_REDESIGN.md for full analysis.
#
# Inputs: IngestItems with completed lexicon extraction
# Outputs: Pool entities (no relationships)
#
module Pools
  class ExtractionJob < Pipeline::BaseJob
    queue_as :pipeline
    
    def perform(pipeline_run_id)
      # BaseJob sets up @pipeline_run, @batch, @ekn via around_perform
      # Do NOT call super - BaseJob uses around_perform to wrap this method
      
      @extracted_entities = []
      items = items_to_process
      
      log_progress "Starting entity extraction for #{items.count} items"
      
      processed = 0
      failed = 0
      
      items.find_each do |item|
        begin
          extract_entities_from_item(item)
          processed += 1
          
          if processed % 10 == 0
            log_progress "Processed #{processed} IngestItems for Ten Pool Canon extraction...", level: :debug
          end
        rescue => e
          log_progress "Failed to process item #{item.id}: #{e.message}", level: :error
          failed += 1
          item.update!(pool_status: 'failed', pool_metadata: { error: e.message })
        end
      end
      
      # Save extracted entities to database
      save_entities_to_database
      
      log_progress "✅ Entity extraction complete: #{processed} processed, #{failed} failed"
      log_progress "   Extracted #{@extracted_entities.size} entities"
      log_progress "   Note: Relationships will be discovered in Stage 5.5 after graph assembly"
      
      # Track metrics
      track_metric :items_processed, processed
      track_metric :items_failed, failed
      track_metric :entities_extracted, @extracted_entities.size
      
      # Update batch status
      @batch.update!(status: 'pool_filling_completed')
    end
    
    private
    
    def items_to_process
      # Only process items that were marked pool-ready by lexicon stage
      # Items with pool_status='skipped' had all duplicate terms and don't need processing
      @batch.ingest_items.where(pool_status: 'pending').where(quarantined: [false, nil])
    end
    
    def extract_entities_from_item(item)
      return if item.content.blank?
      
      # Extract entities using ENHANCED Multi-Pass System (ALL 10 pools)
      entity_result = Mcp::EnhancedExtractAndLinkTool.call(
        text: item.content,
        mode: 'extract',  # Just extraction, no linking
        ekn: @ekn
      )
      
      if entity_result[:error].blank?
        # Enhanced system returns entities_extracted directly
        extracted_entities = entity_result[:entities_extracted] || []
        
        # Track which item these entities came from for proper ProvenanceAndRights  
        entities_with_item = extracted_entities.map do |entity|
          entity.merge(item_id: item.id)
        end
        @extracted_entities.concat(entities_with_item)
        
        # Log quality metrics from enhanced system
        quality = entity_result[:quality_report]
        log_progress "Item #{item.id}: #{extracted_entities.size} entities, quality: #{quality[:overall_quality_score]}" if quality
        
        item.update!(
          pool_status: 'extracted',
          pool_metadata: {
            entities_count: extracted_entities.size,
            pools_found: entity_result.dig(:summary, :pools_found) || [],
            quality_score: quality&.dig(:overall_quality_score),
            extraction_strategy: entity_result[:extraction_strategy],
            extracted_at: Time.current
          },
          graph_status: 'pending'  # CRITICAL: Mark as ready for graph assembly
        )
      else
        raise entity_result[:error]
      end
    end
    
    def get_lexicon_context
      LexiconAndOntology.canonical.limit(100).pluck(:term, :pool_association)
    end
    
    def save_entities_to_database
      return if @extracted_entities.empty?
      
      log_progress "Saving #{@extracted_entities.size} entities to database...", level: :debug
      
      # Group entities by item_id to create proper ProvenanceAndRights
      entities_by_item = @extracted_entities.group_by { |e| e[:item_id] }
      
      entities_by_item.each do |item_id, entities|
        # Get the item for rights information
        item = IngestItem.find_by(id: item_id)
        next unless item
        
        # Create item-specific ProvenanceAndRights
        item_rights = ProvenanceAndRights.find_or_create_by!(
          # Required fields
          source_ids: ["pipeline_extraction_#{@batch.id}_item_#{item_id}"],
          collection_method: "openai_extraction",
          consent_status: "implicit_consent",
          license_type: "custom",
          valid_time_start: Time.current,
          
          # Optional fields
          source_owner: "Enliterator Pipeline",
          
          # Default rights (items don't have these fields)
          publishability: true,
          training_eligibility: true,
          quarantined: false,
          
          # Store extraction metadata with ITEM_ID
          custom_terms: {
            'source_type' => 'extracted_entity',
            'extraction_batch' => @batch.id,
            'extraction_item' => item_id,  # CRITICAL: Track which item!
            'extraction_stage' => 'pool_filling',
            'extraction_timestamp' => Time.current.iso8601
          }
        )
        
        # Save entities from this item
        entities.each do |entity_data|
          begin
            save_entity(entity_data, item_rights)
          rescue => e
            log_progress "Failed to save entity from item #{item_id}: #{e.message}", level: :error
          end
        end
      end
    end
    
    def save_entity(entity_data, rights)
      pool_type = entity_data[:pool_type] || entity_data[:pool]
      attrs = entity_data
      
      # Enhanced system uses direct entity attributes (not nested in :attributes)
      # Convert enhanced system data to compatible format
      if entity_data[:name] && !attrs[:label]
        attrs[:label] = entity_data[:name]
        attrs[:repr_text] = entity_data[:context] || entity_data[:name]
      end
      
      # Skip if no pool type
      return unless pool_type
      
      case pool_type.to_s.downcase
      when 'idea'
        Idea.create!(
          label: attrs[:label] || 'Unknown',
          abstract: attrs[:abstract] || attrs[:repr_text],
          principle_tags: attrs[:principle_tags] || [],
          authorship: attrs[:authorship] || 'Unknown',
          inception_date: attrs[:inception_date] || Time.current,
          valid_time_start: attrs[:valid_time_start] || Time.current,
          repr_text: attrs[:repr_text] || attrs[:label],
          provenance_and_rights: rights
        )
      when 'manifest'
        # Handle time_bounds as JSONB structure
        time_bounds_data = if attrs[:time_bounds_start] || attrs[:time_bounds_end]
          {
            start: (attrs[:time_bounds_start] || Time.current).iso8601,
            end: attrs[:time_bounds_end]&.iso8601
          }.compact
        else
          attrs[:time_bounds] || {}
        end
        
        Manifest.create!(
          label: attrs[:label] || 'Unknown',
          manifest_type: attrs[:manifest_type] || 'artifact',  
          components: attrs[:components] || [],
          time_bounds: time_bounds_data,
          valid_time_start: attrs[:valid_time_start] || Time.current,
          repr_text: attrs[:repr_text] || attrs[:label] || 'Unknown Manifest',
          provenance_and_rights: rights
        )
      when 'experience'
        Experience.create!(
          agent_label: attrs[:agent_label] || 'Unknown',
          context: attrs[:context] || '',
          narrative_text: attrs[:narrative_text] || attrs[:repr_text],
          sentiment: attrs[:sentiment] || 'neutral',
          observed_at: attrs[:observed_at] || Time.current,
          repr_text: attrs[:repr_text] || attrs[:narrative_text],
          provenance_and_rights: rights
        )
      when 'practical'
        safe_goal = attrs[:goal] || attrs[:label] || 'Unknown Practical'
        Practical.create!(
          goal: safe_goal,
          steps: attrs[:steps] || [],
          prerequisites: attrs[:prerequisites] || [],
          hazards: attrs[:hazards] || [],
          validation_refs: attrs[:validation_refs] || [],
          valid_time_start: attrs[:valid_time_start] || Time.current,
          repr_text: attrs[:repr_text] || safe_goal,
          provenance_and_rights: rights
        )
      when 'relational'
        # Note: Relational entities here are entity placeholders, not actual relationships
        # Real relationships are discovered in Stage 5.5
        safe_relation_type = normalize_relation_type(attrs[:relation_type]) || 'relates_to'
        
        # Skip if missing required source/target info
        if attrs[:source_id].blank? || attrs[:target_id].blank?
          log_progress "Skipping relational entity - missing source_id or target_id", level: :debug
          return
        end
        
        Relational.create!(
          relation_type: safe_relation_type,
          source_id: attrs[:source_id],
          source_type: attrs[:source_type] || 'Unknown',
          target_id: attrs[:target_id], 
          target_type: attrs[:target_type] || 'Unknown',
          strength: attrs[:strength] || 0.5,
          valid_time_start: attrs[:valid_time_start] || Time.current,
          repr_text: attrs[:repr_text] || "#{safe_relation_type} relationship",
          provenance_and_rights: rights
        )
      when 'evolutionary'
        Evolutionary.create!(
          change_note: attrs[:change_note] || 'Evolution tracked',
          prior_ref: attrs[:prior_ref],
          version_id: attrs[:version_id] || SecureRandom.uuid,
          valid_time_start: attrs[:valid_time_start] || Time.current,
          provenance_and_rights: rights
        )
      when 'emanation'
        Emanation.create!(
          influence_type: attrs[:influence_type] || 'influence',
          target_context: attrs[:target_context] || '',
          pathway: attrs[:pathway] || '',
          evidence: attrs[:evidence] || '',
          valid_time_start: attrs[:valid_time_start] || Time.current,
          repr_text: attrs[:repr_text] || attrs[:influence_type],
          provenance_and_rights: rights
        )
      when 'character'
        # NEW: Character pool - People, agents, roles, personas
        Character.create!(
          label: attrs[:label] || 'Unknown Person',
          role_type: detect_character_role_type(attrs[:label], attrs[:context]),
          title: extract_title_from_context(attrs[:context]),
          biography: attrs[:context] || attrs[:reasoning],
          active: true,
          has_agency: true,
          valid_time_start: attrs[:valid_time_start] || Time.current,
          repr_text: attrs[:repr_text] || attrs[:label],
          provenance_and_rights: rights,
          batch_id: @batch.id,
          entity_id: generate_entity_id('character')
        )
      when 'time'
        # NEW: Time pool - Temporal entities, periods, schedules  
        TimeEntity.create!(
          label: attrs[:label] || 'Unknown Time',
          temporal_type: detect_temporal_type(attrs[:label], attrs[:context]),
          description: attrs[:context] || attrs[:reasoning],
          start_time: parse_time_from_label(attrs[:label]),
          recurring: attrs[:label]&.include?('annual') || attrs[:label]&.include?('seasonal'),
          valid_time_start: attrs[:valid_time_start] || Time.current,
          repr_text: attrs[:repr_text] || attrs[:label],
          provenance_and_rights: rights,
          batch_id: @batch.id,
          entity_id: generate_entity_id('time')
        )
      when 'space'
        # NEW: Space pool - Locations, places, geographic entities
        Space.create!(
          label: attrs[:label] || 'Unknown Location',
          spatial_type: detect_spatial_type(attrs[:label], attrs[:context]),
          region: extract_region_from_context(attrs[:context]),
          description: attrs[:context] || attrs[:reasoning],
          valid_time_start: attrs[:valid_time_start] || Time.current,
          repr_text: attrs[:repr_text] || attrs[:label],
          provenance_and_rights: rights,
          batch_id: @batch.id,
          entity_id: generate_entity_id('space')
        )
      when 'lifecycle'
        # NEW: Lifecycle pool - States, transitions, progressions, phases
        Lifecycle.create!(
          label: attrs[:label] || 'Unknown Stage',
          stage_type: detect_stage_type(attrs[:label], attrs[:context]),
          sequence_order: extract_sequence_order(attrs[:label]),
          is_active: true,
          description: attrs[:context] || attrs[:reasoning],
          valid_time_start: attrs[:valid_time_start] || Time.current,
          repr_text: attrs[:repr_text] || attrs[:label],
          provenance_and_rights: rights,
          batch_id: @batch.id,
          entity_id: generate_entity_id('lifecycle')
        )
      when 'symbolic'
        # NEW: Symbolic pool - Symbols, meanings, representations, metaphors
        Symbolic.create!(
          label: attrs[:label] || 'Unknown Symbol',
          symbol_type: detect_symbol_type(attrs[:label], attrs[:context]),
          meaning: attrs[:reasoning] || extract_meaning_from_context(attrs[:context]),
          cultural_context: extract_cultural_context(attrs[:context]),
          valid_time_start: attrs[:valid_time_start] || Time.current,
          repr_text: attrs[:repr_text] || attrs[:label],
          provenance_and_rights: rights,
          batch_id: @batch.id,
          entity_id: generate_entity_id('symbolic')
        )
      when 'relator'
        # NEW: Relator pool - Relationships, connections, dependencies
        Relator.create!(
          label: attrs[:label] || 'Unknown Relationship',
          relation_type: detect_relation_type(attrs[:label], attrs[:context]),
          source_label: extract_source_from_context(attrs[:context]),
          target_label: extract_target_from_context(attrs[:context]),
          strength: attrs[:confidence] || 0.7,
          bidirectional: detect_bidirectional(attrs[:context]),
          description: attrs[:context] || attrs[:reasoning],
          valid_time_start: attrs[:valid_time_start] || Time.current,
          repr_text: attrs[:repr_text] || attrs[:label],
          provenance_and_rights: rights,
          batch_id: @batch.id,
          entity_id: generate_entity_id('relator')
        )
      else
        log_progress "Unknown pool type: #{pool_type}", level: :warn
      end
    end
    
    def collect_stage_metrics
      {
        items_processed: @metrics[:items_processed] || 0,
        items_failed: @metrics[:items_failed] || 0,
        entities_extracted: @metrics[:entities_extracted] || 0
        # Note: relations_extracted removed - relationships discovered in Stage 5.5
      }
    end
    
    # Helper to normalize relation types to valid enum values
    def normalize_relation_type(raw_type)
      return nil if raw_type.blank?
      
      # Convert spaces and hyphens to underscores, downcase
      normalized = raw_type.to_s.gsub(/[\s\-]+/, '_').downcase
      
      # Direct mapping for known Arctic Research terms
      mappings = {
        'bilateral_cooperation' => 'bilateral_cooperation',
        'bilateral_partnership' => 'bilateral_partnership', 
        'partnership' => 'partnership',
        'cooperation' => 'cooperation',
        'interdependence' => 'interdependence',
        'collaboration' => 'collaboration',
        'alliance' => 'alliance',
        'agreement' => 'agreement',
        'treaty' => 'treaty'
      }
      
      # Check if normalized type exists in mappings or is valid enum
      mappings[normalized] || (Relational.relation_types.key?(normalized) ? normalized : 'relates_to')
    end
    
    # Helper methods for NEW pool types
    
    def detect_character_role_type(label, context)
      text = "#{label} #{context}".downcase
      return 'individual' if text.match?(/dr\.|professor|ph\.d|researcher/)
      return 'organization' if text.match?(/university|agency|institute|department/)
      return 'team' if text.match?(/team|group|community|collective/)
      return 'role_position' if text.match?(/elder|leader|member|coordinator/)
      'individual'
    end
    
    def extract_title_from_context(context)
      return nil unless context
      # Extract titles like "Dr.", "Professor", "Elder"
      match = context.match(/(Dr\.|Professor|Elder|Chief|Director)/)
      match ? match[1] : nil
    end
    
    def detect_temporal_type(label, context)
      text = "#{label} #{context}".downcase
      return 'period' if text.match?(/\d{4}[-–]\d{4}|period|span/)
      return 'season' if text.match?(/winter|spring|summer|fall|autumn|seasonal/)
      return 'schedule' if text.match?(/daily|weekly|monthly|routine|schedule/)
      return 'event' if text.match?(/expedition|meeting|conference|workshop/)
      'period'
    end
    
    def parse_time_from_label(label)
      return nil unless label
      # Extract years like "2020-2023" or "2019"  
      if label.match(/(\d{4})[-–](\d{4})/)
        Date.new($1.to_i, 1, 1)
      elsif label.match(/(\d{4})/)
        Date.new($1.to_i, 1, 1)
      else
        nil
      end
    rescue
      nil
    end
    
    def detect_spatial_type(label, context)
      text = "#{label} #{context}".downcase
      return 'facility' if text.match?(/station|facility|building|laboratory/)
      return 'region' if text.match?(/arctic|northern|region|area|zone/)
      return 'administrative' if text.match?(/borough|county|district|territory/)
      return 'geographic' if text.match?(/sea|ocean|mountain|river|lake/)
      'geographic'
    end
    
    def extract_region_from_context(context)
      return nil unless context
      # Extract regional references
      regions = %w[Alaska Arctic Northern Beaufort Slope]
      regions.find { |r| context.include?(r) }
    end
    
    def detect_stage_type(label, context)
      text = "#{label} #{context}".downcase
      return 'phase' if text.match?(/phase|stage \d+|step \d+/)
      return 'cyclical' if text.match?(/cycle|annual|seasonal|recurring/)
      return 'transition' if text.match?(/melting|formation|change|transition/)
      return 'workflow' if text.match?(/process|methodology|procedure/)
      'phase'
    end
    
    def extract_sequence_order(label)
      return nil unless label
      # Extract numbers from "Phase 1", "Step 2", etc.
      match = label.match(/(?:phase|step|stage)\s*(\d+)/i)
      match ? match[1].to_i : nil
    end
    
    def detect_symbol_type(label, context)
      text = "#{label} #{context}".downcase
      return 'metaphor' if text.match?(/memory|symbol|represent|metaphor/)
      return 'cultural' if text.match?(/cultural|traditional|ancestral|sacred/)
      return 'meaning' if text.match?(/meaning|significance|importance/)
      'symbol'
    end
    
    def extract_meaning_from_context(context)
      return nil unless context
      # Extract explanatory text after quotes or descriptions
      match = context.match(/"[^"]*"\s*[-–]\s*(.+)/)
      match ? match[1].strip : context
    end
    
    def extract_cultural_context(context)
      return nil unless context
      # Extract cultural references
      cultures = %w[Inupiat Indigenous Native Traditional Arctic]
      cultures.find { |c| context.include?(c) }
    end
    
    def detect_relation_type(label, context)
      text = "#{label} #{context}".downcase
      return 'causation' if text.match?(/cause|effect|leads to|results in/)
      return 'correlation' if text.match?(/correlation|relationship|between/)
      return 'dependency' if text.match?(/depends|requires|needs/)
      return 'influence' if text.match?(/influence|impact|affect/)
      return 'linkage' if text.match?(/connect|link|join|bridge/)
      'association'
    end
    
    def extract_source_from_context(context)
      return nil unless context
      # Extract "X affects Y" patterns
      match = context.match(/(\w+(?:\s+\w+)*)\s+(?:affects?|influences?|causes?|leads to)/i)
      match ? match[1] : nil
    end
    
    def extract_target_from_context(context)
      return nil unless context  
      # Extract "X affects Y" patterns
      match = context.match(/(?:affects?|influences?|causes?|leads to)\s+(\w+(?:\s+\w+)*)/i)
      match ? match[1] : nil
    end
    
    def detect_bidirectional(context)
      return false unless context
      context.downcase.include?('bidirectional') || context.downcase.include?('mutual')
    end
    
    def generate_entity_id(pool_type)
      "#{pool_type}_#{Time.current.to_i}_#{SecureRandom.hex(4)}"
    end
  end
end