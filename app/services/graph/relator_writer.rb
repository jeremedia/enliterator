# frozen_string_literal: true

module Graph
  # Service to sync Relator entities to the Neo4j graph database as Relational nodes
  # Maps PostgreSQL Relator records to Neo4j Relational nodes (Ten Pool Canon)
  class RelatorWriter
    def initialize(relator)
      @relator = relator
      @database_name = determine_database_name
    end

    def sync
      Rails.logger.info "Syncing Relator #{@relator.id} as Relational to Neo4j database: #{@database_name}"
      
      driver = Graph::Connection.instance.driver
      session = driver.session(database: @database_name)
      
      session.write_transaction do |tx|
        # Create or update the Relational node (mapping Relator -> Relational)
        create_or_update_node(tx)
        
        # Create rights relationship
        create_rights_relationship(tx)
      end
      
      session.close
      true
    rescue StandardError => e
      Rails.logger.error "Failed to sync Relator #{@relator.id} as Relational: #{e.message}"
      false
    ensure
      session&.close
    end
    
    private
    
    def determine_database_name
      if @relator.batch_id
        # Find the batch and get its EKN database
        batch = IngestBatch.find(@relator.batch_id)
        batch.ensure_neo4j_database_exists!
        batch.neo4j_database_name
      else
        # Fallback to default database
        'neo4j'
      end
    end
    
    def create_or_update_node(tx)
      properties = {
        id: @relator.id,
        label: @relator.label,
        relation_type: @relator.relation_type,
        source_label: @relator.source_label,
        target_label: @relator.target_label,
        strength: @relator.strength,
        bidirectional: @relator.bidirectional,
        repr_text: @relator.repr_text,
        valid_time_start: @relator.valid_time_start.to_s,
        valid_time_end: @relator.valid_time_end&.to_s,
        created_at: @relator.created_at.to_s,
        updated_at: @relator.updated_at.to_s,
        batch_id: @relator.batch_id,
        # Map Relator fields to Relational pool semantics  
        source: @relator.source_label || "",
        target: @relator.target_label || "",
        period: "active"
      }.compact
      
      query = <<~CYPHER
        MERGE (n:Relational {id: $id})
        SET n += $properties
      CYPHER
      
      tx.run(query, id: @relator.id, properties: properties)
    end
    
    def create_rights_relationship(tx)
      return unless @relator.provenance_and_rights_id
      
      # Create relationship to ProvenanceAndRights node
      query = <<~CYPHER
        MATCH (relational:Relational {id: $relational_id})
        MATCH (rights:ProvenanceAndRights {id: $rights_id})
        MERGE (relational)-[r:HAS_RIGHTS]->(rights)
        SET r.created_at = timestamp()
      CYPHER
      
      tx.run(query, relational_id: @relator.id, rights_id: @relator.provenance_and_rights_id)
    rescue Neo4j::Driver::Exceptions::ClientException => e
      Rails.logger.warn "Could not create rights relationship for Relational #{@relator.id}: #{e.message}"
    end
  end
end