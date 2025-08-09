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
      
      # Extract entities ONLY (no relationships at this stage)
      entity_result = Pools::EntityExtractionService.new(
        content: item.content,
        lexicon_context: get_lexicon_context,
        source_metadata: item.metadata
      ).extract
      
      if entity_result[:success]
        # Track which item these entities came from for proper ProvenanceAndRights
        entities_with_item = (entity_result[:entities] || []).map do |entity|
          entity.merge(item_id: item.id)
        end
        @extracted_entities.concat(entities_with_item)
        
        item.update!(
          pool_status: 'extracted',
          pool_metadata: {
            entities_count: entity_result[:entities]&.size || 0,
            # Note: relations_count removed - relationships discovered later
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
          
          # Inherit rights from item
          publishability: item.publishability || true,
          training_eligibility: item.training_eligibility || true,
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
      attrs = entity_data[:attributes] || entity_data
      
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
        Manifest.create!(
          label: attrs[:label] || 'Unknown',
          manifest_type: attrs[:manifest_type] || 'artifact',
          components: attrs[:components] || [],
          time_bounds_start: attrs[:time_bounds_start] || Time.current,
          valid_time_start: attrs[:valid_time_start] || Time.current,
          repr_text: attrs[:repr_text] || attrs[:label],
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
        Practical.create!(
          goal: attrs[:goal] || attrs[:label] || 'Unknown',
          steps: attrs[:steps] || [],
          prerequisites: attrs[:prerequisites] || [],
          hazards: attrs[:hazards] || [],
          validation_refs: attrs[:validation_refs] || [],
          valid_time_start: attrs[:valid_time_start] || Time.current,
          repr_text: attrs[:repr_text] || attrs[:goal],
          provenance_and_rights: rights
        )
      when 'relational'
        # Note: Relational entities here are entity placeholders, not actual relationships
        # Real relationships are discovered in Stage 5.5
        Relational.create!(
          relation_type: attrs[:relation_type] || 'placeholder',
          source_id: attrs[:source_id],
          source_type: attrs[:source_type] || 'Unknown',
          target_id: attrs[:target_id],
          target_type: attrs[:target_type] || 'Unknown',
          strength: attrs[:strength] || 0.5,
          valid_time_start: attrs[:valid_time_start] || Time.current,
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
  end
end