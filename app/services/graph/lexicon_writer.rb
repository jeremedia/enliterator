# frozen_string_literal: true

module Graph
  # Service to sync lexicon entries to the Neo4j graph database
  # Supports database-per-EKN isolation
  class LexiconWriter
    def initialize(lexicon_entry, ingest_batch = nil)
      @entry = lexicon_entry
      @batch = ingest_batch
      @database_name = determine_database_name
    end

    def sync
      Rails.logger.info "Syncing LexiconAndOntology #{@entry.id} to Neo4j database: #{@database_name}"
      
      driver = Graph::Connection.instance.driver
      session = driver.session(database: @database_name)
      
      session.write_transaction do |tx|
        # Create or update the Lexicon node
        create_or_update_node(tx)
        
        # Create relationships to normalized entities
        create_normalization_relationships(tx) if @entry.type_mapping.present?
        
        # Create relationships to related terms
        create_term_relationships(tx)
      end
      
      session.close
      true
    rescue StandardError => e
      Rails.logger.error "Failed to sync lexicon entry #{@entry.id}: #{e.message}"
      false
    ensure
      session&.close
    end
    
    private
    
    def determine_database_name
      if @batch
        @batch.ensure_neo4j_database_exists!
        @batch.neo4j_database_name
      else
        # Fallback to default database for backward compatibility
        'neo4j'
      end
    end
    
    def create_or_update_node(tx)
      properties = {
        id: @entry.id,
        term: @entry.term,
        definition: @entry.definition,
        canonical_description: @entry.canonical_description,
        surface_forms: @entry.surface_forms || [],
        negative_surface_forms: @entry.negative_surface_forms || [],
        type_mapping: @entry.type_mapping&.to_json,
        unit_system: @entry.unit_system,
        schema_version: @entry.schema_version,
        valid_time_start: @entry.valid_time_start.to_s,
        valid_time_end: @entry.valid_time_end&.to_s,
        created_at: @entry.created_at.to_s,
        updated_at: @entry.updated_at.to_s
      }.compact
      
      query = <<~CYPHER
        MERGE (n:Lexicon {id: $id})
        SET n += $properties
      CYPHER
      
      tx.run(query, id: @entry.id, properties: properties)
    end
    
    def create_normalization_relationships(tx)
      pool_type = @entry.type_mapping['pool']
      entity_id = @entry.type_mapping['entity_id']
      
      return unless pool_type && entity_id
      
      # Create relationship from Lexicon to the normalized entity
      query = <<~CYPHER
        MATCH (lexicon:Lexicon {id: $lexicon_id})
        MATCH (entity:#{pool_type.capitalize} {id: $entity_id})
        MERGE (lexicon)-[r:NORMALIZES]->(entity)
        SET r.created_at = timestamp()
      CYPHER
      
      tx.run(query, lexicon_id: @entry.id, entity_id: entity_id)
    rescue Neo4j::Driver::Exceptions::ClientException => e
      Rails.logger.warn "Could not create normalization relationship: #{e.message}"
    end
    
    def create_term_relationships(tx)
      # Create relationships to broader, narrower, and related terms if they exist
      
      if @entry.respond_to?(:broader_term_id) && @entry.broader_term_id
        create_term_relationship(tx, @entry.broader_term_id, 'BROADER_THAN')
      end
      
      if @entry.respond_to?(:narrower_term_ids) && @entry.narrower_term_ids.present?
        @entry.narrower_term_ids.each do |narrower_id|
          create_term_relationship(tx, narrower_id, 'NARROWER_THAN')
        end
      end
      
      if @entry.respond_to?(:related_term_ids) && @entry.related_term_ids.present?
        @entry.related_term_ids.each do |related_id|
          create_term_relationship(tx, related_id, 'RELATED_TO')
        end
      end
    end
    
    def create_term_relationship(tx, target_id, relationship_type)
      query = <<~CYPHER
        MATCH (source:Lexicon {id: $source_id})
        MATCH (target:Lexicon {id: $target_id})
        MERGE (source)-[r:#{relationship_type}]->(target)
        SET r.created_at = timestamp()
      CYPHER
      
      tx.run(query, source_id: @entry.id, target_id: target_id)
    rescue Neo4j::Driver::Exceptions::ClientException => e
      Rails.logger.warn "Could not create #{relationship_type} relationship: #{e.message}"
    end
  end
end