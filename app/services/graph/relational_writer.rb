# frozen_string_literal: true

module Graph
  # Service to sync Relational entities to the Neo4j graph database
  # Maps PostgreSQL Relational records to Neo4j Relational nodes
  class RelationalWriter
    def initialize(relational)
      @relational = relational
      @database_name = determine_database_name
    end

    def sync
      Rails.logger.info "Syncing Relational #{@relational.id} to Neo4j database: #{@database_name}"
      
      driver = Graph::Connection.instance.driver
      session = driver.session(database: @database_name)
      
      session.write_transaction do |tx|
        # Create or update the Relational node
        create_or_update_node(tx)
        
        # Create rights relationship
        create_rights_relationship(tx)
        
        # Create source/target relationships if applicable
        create_entity_relationships(tx)
      end
      
      session.close
      true
    rescue StandardError => e
      Rails.logger.error "Failed to sync Relational #{@relational.id}: #{e.message}"
      false
    ensure
      session&.close
    end
    
    private
    
    def determine_database_name
      if @relational.batch_id
        # Find the batch and get its EKN database
        batch = IngestBatch.find(@relational.batch_id)
        batch.ensure_neo4j_database_exists!
        batch.neo4j_database_name
      else
        # Fallback to default database
        'neo4j'
      end
    end
    
    def create_or_update_node(tx)
      properties = {
        id: @relational.id,
        relation_type: @relational.relation_type,
        source: @relational.source,
        target: @relational.target,
        strength: @relational.strength,
        period: @relational.period,
        repr_text: @relational.repr_text,
        valid_time_start: @relational.valid_time_start.to_s,
        valid_time_end: @relational.valid_time_end&.to_s,
        created_at: @relational.created_at.to_s,
        updated_at: @relational.updated_at.to_s,
        batch_id: @relational.batch_id
      }.compact
      
      query = <<~CYPHER
        MERGE (n:Relational {id: $id})
        SET n += $properties
      CYPHER
      
      tx.run(query, id: @relational.id, properties: properties)
    end
    
    def create_rights_relationship(tx)
      return unless @relational.provenance_and_rights_id
      
      # Create relationship to ProvenanceAndRights node
      query = <<~CYPHER
        MATCH (relational:Relational {id: $relational_id})
        MATCH (rights:ProvenanceAndRights {id: $rights_id})
        MERGE (relational)-[r:HAS_RIGHTS]->(rights)
        SET r.created_at = timestamp()
      CYPHER
      
      tx.run(query, relational_id: @relational.id, rights_id: @relational.provenance_and_rights_id)
    rescue Neo4j::Driver::Exceptions::ClientException => e
      Rails.logger.warn "Could not create rights relationship for Relational #{@relational.id}: #{e.message}"
    end
    
    def create_entity_relationships(tx)
      # Note: The Relational entity itself represents connections between entities
      # The source/target fields contain string references that would need to be
      # resolved to actual entity IDs for creating graph relationships
      # This is a placeholder for more sophisticated relationship creation logic
      
      Rails.logger.debug "Relational #{@relational.id} represents connection: #{@relational.source} -> #{@relational.target}"
    rescue StandardError => e
      Rails.logger.warn "Could not process entity relationships for Relational #{@relational.id}: #{e.message}"
    end
  end
end