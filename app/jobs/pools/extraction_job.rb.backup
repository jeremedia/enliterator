# frozen_string_literal: true

module Pools
  # Job to extract entities and relations for the Ten Pool Canon
  # This is Stage 4 of the Zero-touch Pipeline
  # - Extracts entities for all required pools
  # - Assigns ids, time fields, and rights pointers
  # - Builds cross-pool edges using the Relation Verb Glossary
  # - Records path provenance
  class ExtractionJob < ApplicationJob
    queue_as :pipeline
    
    # Relation Verb Glossary from spec
    VERB_GLOSSARY = {
      'embodies' => { source: 'Idea', target: 'Manifest', reverse: 'is_embodiment_of' },
      'elicits' => { source: 'Manifest', target: 'Experience', reverse: 'is_elicited_by' },
      'influences' => { source: %w[Idea Emanation], target: '*', reverse: 'is_influenced_by' },
      'refines' => { source: 'Evolutionary', target: 'Idea', reverse: 'is_refined_by' },
      'version_of' => { source: 'Evolutionary', target: 'Manifest', reverse: 'has_version' },
      'co_occurs_with' => { source: 'Relational', target: 'Relational', symmetric: true },
      'located_at' => { source: 'Manifest', target: 'Spatial', reverse: 'hosts' },
      'adjacent_to' => { source: 'Spatial', target: 'Spatial', symmetric: true },
      'validated_by' => { source: 'Practical', target: 'Experience', reverse: 'validates' },
      'supports' => { source: 'Evidence', target: 'Idea', reverse: nil },
      'refutes' => { source: 'Evidence', target: 'Idea', reverse: nil },
      'diffuses_through' => { source: 'Emanation', target: 'Relational', reverse: nil }
    }.freeze

    def perform(ingest_batch_id)
      @batch = IngestBatch.find(ingest_batch_id)
      @extracted_entities = []
      @extracted_relations = []
      @path_provenance = []
      
      Rails.logger.info "Starting pool filling for batch #{@batch.id}"
      
      # Update batch status
      @batch.update!(status: 'pool_filling_in_progress')
      
      # Process items that have completed lexicon extraction
      @batch.ingest_items.where(lexicon_status: 'extracted').find_each do |item|
        extract_pools_from_item(item)
      end
      
      # Create entities and relations
      create_entities
      create_relations
      
      finalize_batch_pool_filling
    rescue StandardError => e
      Rails.logger.error "Failed to fill pools for batch #{@batch.id}: #{e.message}"
      @batch.update!(status: 'failed', metadata: @batch.metadata.merge(
        pool_filling_error: { message: e.message, backtrace: e.backtrace.first(5) }
      ))
      raise
    end

    private

    def extract_pools_from_item(item)
      return if item.content.blank?
      
      # Extract entities using OpenAI
      entity_result = Pools::EntityExtractionService.new(
        content: item.content,
        lexicon_context: get_lexicon_context,
        source_metadata: item.metadata
      ).extract
      
      if entity_result[:success]
        # Process extracted entities
        entity_result[:entities].each do |entity_data|
          @extracted_entities << prepare_entity(entity_data, item)
        end
        
        # Extract relations
        relation_result = Pools::RelationExtractionService.new(
          content: item.content,
          entities: entity_result[:entities],
          verb_glossary: VERB_GLOSSARY
        ).extract
        
        if relation_result[:success]
          @extracted_relations.concat(relation_result[:relations])
        end
        
        # Record path provenance
        record_provenance(item, entity_result, relation_result)
        
        # Update item status
        item.update!(
          pool_status: 'extracted',
          pool_metadata: {
            entities_count: entity_result[:entities].size,
            relations_count: relation_result[:relations].size,
            extracted_at: Time.current
          }
        )
      else
        handle_extraction_failure(item, entity_result)
      end
    rescue StandardError => e
      Rails.logger.error "Error processing item #{item.id}: #{e.message}"
      item.update!(
        pool_status: 'failed',
        pool_metadata: { error: e.message }
      )
    end
    
    def get_lexicon_context
      # Get canonical terms from lexicon for better extraction
      LexiconAndOntology.canonical.limit(100).pluck(:term, :pool_association, :canonical_description)
    end
    
    def prepare_entity(entity_data, source_item)
      {
        pool_type: entity_data[:pool_type],
        attributes: entity_data[:attributes].merge(
          # Ensure required fields
          valid_time_start: entity_data[:attributes][:valid_time_start] || Time.current,
          provenance_and_rights_id: source_item.provenance_and_rights_id
        ),
        source_item_id: source_item.id,
        extraction_confidence: entity_data[:confidence]
      }
    end
    
    def record_provenance(item, entity_result, relation_result)
      @path_provenance << {
        source_item_id: item.id,
        extraction_path: "IngestItem(#{item.id}) → extract → #{entity_result[:entities].size} entities + #{relation_result[:relations].size} relations",
        extraction_metadata: {
          entity_pools: entity_result[:entities].map { |e| e[:pool_type] }.uniq,
          relation_verbs: relation_result[:relations].map { |r| r[:verb] }.uniq,
          timestamp: Time.current
        }
      }
    end
    
    def create_entities
      @extracted_entities.group_by { |e| e[:pool_type] }.each do |pool_type, entities|
        model_class = pool_type.classify.constantize
        
        entities.each do |entity_data|
          # Create entity with rights pointer
          entity = model_class.create!(entity_data[:attributes])
          
          # Store mapping for relation creation
          entity_data[:created_id] = entity.id
          entity_data[:created_class] = model_class.name
        end
      end
    end
    
    def create_relations
      @extracted_relations.each do |relation_data|
        # Find source and target entities
        source = find_entity(relation_data[:source])
        target = find_entity(relation_data[:target])
        
        next unless source && target
        
        # Create relation based on verb
        create_relation(source, target, relation_data[:verb])
      end
    end
    
    def find_entity(entity_ref)
      # Find entity by pool type and identifier
      pool_class = entity_ref[:pool_type].classify.constantize
      pool_class.find_by(label: entity_ref[:label]) ||
        pool_class.find_by(id: entity_ref[:id])
    end
    
    def create_relation(source, target, verb)
      # Create relation using join tables
      case verb
      when 'embodies'
        IdeaManifest.find_or_create_by!(idea: source, manifest: target)
      when 'elicits'
        ManifestExperience.find_or_create_by!(manifest: source, experience: target)
      when 'influences'
        if source.is_a?(Idea)
          IdeaEmanation.find_or_create_by!(idea: source, emanation: target)
        end
      # Add other verb handlers...
      end
    end
    
    def handle_extraction_failure(item, result)
      Rails.logger.warn "Failed to extract pools from item #{item.id}: #{result[:error]}"
      item.update!(
        pool_status: 'failed',
        pool_metadata: { error: result[:error] }
      )
    end
    
    def finalize_batch_pool_filling
      # Count results
      successful_items = @batch.ingest_items.where(pool_status: 'extracted').count
      failed_items = @batch.ingest_items.where(pool_status: 'failed').count
      
      # Count created entities by pool
      pool_counts = {}
      %w[Idea Manifest Experience Relational Evolutionary Practical Emanation].each do |pool|
        pool_counts[pool.underscore] = pool.constantize.where(
          created_at: @batch.created_at..Time.current
        ).count
      end
      
      # Update batch metadata
      @batch.update!(
        status: 'pool_filling_completed',
        metadata: @batch.metadata.merge(
          pool_filling_results: {
            successful_items: successful_items,
            failed_items: failed_items,
            entities_created: @extracted_entities.size,
            relations_created: @extracted_relations.size,
            pool_counts: pool_counts,
            path_provenance_count: @path_provenance.size,
            completed_at: Time.current
          }
        )
      )
      
      Rails.logger.info "Pool filling completed for batch #{@batch.id}: #{successful_items} items processed"
      
      # Trigger next stage if successful
      if failed_items == 0 || failed_items < successful_items * 0.1 # Less than 10% failed
        # TODO: Trigger Stage 5 - Graph Assembly
        # Graph::AssemblyJob.perform_later(@batch.id)
        Rails.logger.info "Batch #{@batch.id} ready for graph assembly stage"
      end
    end
  end
end