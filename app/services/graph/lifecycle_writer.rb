# frozen_string_literal: true

module Graph
  # Service to sync Lifecycle entities to the Neo4j graph database as Evolutionary nodes
  # Maps PostgreSQL Lifecycle records to Neo4j Evolutionary nodes (Ten Pool Canon)
  class LifecycleWriter
    def initialize(lifecycle)
      @lifecycle = lifecycle
      @database_name = determine_database_name
    end

    def sync
      Rails.logger.info "Syncing Lifecycle #{@lifecycle.id} as Evolutionary to Neo4j database: #{@database_name}"
      
      driver = Graph::Connection.instance.driver
      session = driver.session(database: @database_name)
      
      session.write_transaction do |tx|
        # Create or update the Evolutionary node (mapping Lifecycle -> Evolutionary)
        create_or_update_node(tx)
        
        # Create rights relationship
        create_rights_relationship(tx)
      end
      
      session.close
      true
    rescue StandardError => e
      Rails.logger.error "Failed to sync Lifecycle #{@lifecycle.id} as Evolutionary: #{e.message}"
      false
    ensure
      session&.close
    end
    
    private
    
    def determine_database_name
      if @lifecycle.batch_id
        # Find the batch and get its EKN database
        batch = IngestBatch.find(@lifecycle.batch_id)
        batch.ensure_neo4j_database_exists!
        batch.neo4j_database_name
      else
        # Fallback to default database
        'neo4j'
      end
    end
    
    def create_or_update_node(tx)
      properties = {
        id: @lifecycle.id,
        label: @lifecycle.label,
        stage_type: @lifecycle.stage_type,
        sequence_order: @lifecycle.sequence_order,
        is_active: @lifecycle.is_active,
        description: @lifecycle.description,
        repr_text: @lifecycle.repr_text,
        valid_time_start: @lifecycle.valid_time_start.to_s,
        valid_time_end: @lifecycle.valid_time_end&.to_s,
        created_at: @lifecycle.created_at.to_s,
        updated_at: @lifecycle.updated_at.to_s,
        batch_id: @lifecycle.batch_id,
        # Map Lifecycle fields to Evolutionary pool semantics
        change_note: @lifecycle.description || "Lifecycle process",
        version_id: @lifecycle.sequence_order&.to_s || "unknown",
        change_summary: @lifecycle.label,
        prior_ref_type: "Lifecycle",
        prior_ref_id: @lifecycle.id
      }.compact
      
      query = <<~CYPHER
        MERGE (n:Evolutionary {id: $id})
        SET n += $properties
      CYPHER
      
      tx.run(query, id: @lifecycle.id, properties: properties)
    end
    
    def create_rights_relationship(tx)
      return unless @lifecycle.provenance_and_rights_id
      
      # Create relationship to ProvenanceAndRights node
      query = <<~CYPHER
        MATCH (evolutionary:Evolutionary {id: $evolutionary_id})
        MATCH (rights:ProvenanceAndRights {id: $rights_id})
        MERGE (evolutionary)-[r:HAS_RIGHTS]->(rights)
        SET r.created_at = timestamp()
      CYPHER
      
      tx.run(query, evolutionary_id: @lifecycle.id, rights_id: @lifecycle.provenance_and_rights_id)
    rescue Neo4j::Driver::Exceptions::ClientException => e
      Rails.logger.warn "Could not create rights relationship for Evolutionary #{@lifecycle.id}: #{e.message}"
    end
  end
end