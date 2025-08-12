# frozen_string_literal: true

module Graph
  # Service to sync Practical entities to the Neo4j graph database
  # Maps PostgreSQL Practical records to Neo4j Practical nodes
  class PracticalWriter
    def initialize(practical)
      @practical = practical
      @database_name = determine_database_name
    end

    def sync
      Rails.logger.info "Syncing Practical #{@practical.id} to Neo4j database: #{@database_name}"
      
      driver = Graph::Connection.instance.driver
      session = driver.session(database: @database_name)
      
      session.write_transaction do |tx|
        # Create or update the Practical node
        create_or_update_node(tx)
        
        # Create rights relationship
        create_rights_relationship(tx)
      end
      
      session.close
      true
    rescue StandardError => e
      Rails.logger.error "Failed to sync Practical #{@practical.id}: #{e.message}"
      false
    ensure
      session&.close
    end
    
    private
    
    def determine_database_name
      if @practical.batch_id
        # Find the batch and get its EKN database
        batch = IngestBatch.find(@practical.batch_id)
        batch.ensure_neo4j_database_exists!
        batch.neo4j_database_name
      else
        # Fallback to default database
        'neo4j'
      end
    end
    
    def create_or_update_node(tx)
      properties = {
        id: @practical.id,
        goal: @practical.goal,
        steps: @practical.steps || [],
        prerequisites: @practical.prerequisites || [],
        hazards: @practical.hazards || [],
        validation_refs: @practical.validation_refs || [],
        repr_text: @practical.repr_text,
        valid_time_start: @practical.valid_time_start.to_s,
        valid_time_end: @practical.valid_time_end&.to_s,
        created_at: @practical.created_at.to_s,
        updated_at: @practical.updated_at.to_s,
        batch_id: @practical.batch_id
      }.compact
      
      query = <<~CYPHER
        MERGE (n:Practical {id: $id})
        SET n += $properties
      CYPHER
      
      tx.run(query, id: @practical.id, properties: properties)
    end
    
    def create_rights_relationship(tx)
      return unless @practical.provenance_and_rights_id
      
      # Create relationship to ProvenanceAndRights node
      query = <<~CYPHER
        MATCH (practical:Practical {id: $practical_id})
        MATCH (rights:ProvenanceAndRights {id: $rights_id})
        MERGE (practical)-[r:HAS_RIGHTS]->(rights)
        SET r.created_at = timestamp()
      CYPHER
      
      tx.run(query, practical_id: @practical.id, rights_id: @practical.provenance_and_rights_id)
    rescue Neo4j::Driver::Exceptions::ClientException => e
      Rails.logger.warn "Could not create rights relationship for Practical #{@practical.id}: #{e.message}"
    end
  end
end