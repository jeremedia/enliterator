# frozen_string_literal: true

module Graph
  # Service to sync TimeEntity entities to the Neo4j graph database as Method nodes
  # Maps PostgreSQL TimeEntity records to Neo4j Method nodes (Ten Pool Canon)
  class MethodWriter
    def initialize(time_entity)
      @time_entity = time_entity
      @database_name = determine_database_name
    end

    def sync
      Rails.logger.info "Syncing TimeEntity #{@time_entity.id} as Method to Neo4j database: #{@database_name}"
      
      driver = Graph::Connection.instance.driver
      session = driver.session(database: @database_name)
      
      session.write_transaction do |tx|
        # Create or update the Method node (mapping TimeEntity -> Method)
        create_or_update_node(tx)
        
        # Create rights relationship
        create_rights_relationship(tx)
      end
      
      session.close
      true
    rescue StandardError => e
      Rails.logger.error "Failed to sync TimeEntity #{@time_entity.id} as Method: #{e.message}"
      false
    ensure
      session&.close
    end
    
    private
    
    def determine_database_name
      if @time_entity.batch_id
        # Find the batch and get its EKN database
        batch = IngestBatch.find(@time_entity.batch_id)
        batch.ensure_neo4j_database_exists!
        batch.neo4j_database_name
      else
        # Fallback to default database
        'neo4j'
      end
    end
    
    def create_or_update_node(tx)
      properties = {
        id: @time_entity.id,
        label: @time_entity.label,
        temporal_type: @time_entity.temporal_type,
        start_time: @time_entity.start_time&.to_s,
        end_time: @time_entity.end_time&.to_s,
        duration: @time_entity.duration,
        recurrence_pattern: @time_entity.recurrence_pattern,
        description: @time_entity.description,
        repr_text: @time_entity.repr_text,
        valid_time_start: @time_entity.valid_time_start.to_s,
        valid_time_end: @time_entity.valid_time_end&.to_s,
        created_at: @time_entity.created_at.to_s,
        updated_at: @time_entity.updated_at.to_s,
        batch_id: @time_entity.batch_id,
        # Map TimeEntity fields to Method pool semantics
        method_name: @time_entity.label,
        method_type: @time_entity.temporal_type,
        method_description: @time_entity.description
      }.compact
      
      query = <<~CYPHER
        MERGE (n:Method {id: $id})
        SET n += $properties
      CYPHER
      
      tx.run(query, id: @time_entity.id, properties: properties)
    end
    
    def create_rights_relationship(tx)
      return unless @time_entity.provenance_and_rights_id
      
      # Create relationship to ProvenanceAndRights node
      query = <<~CYPHER
        MATCH (method:Method {id: $method_id})
        MATCH (rights:ProvenanceAndRights {id: $rights_id})
        MERGE (method)-[r:HAS_RIGHTS]->(rights)
        SET r.created_at = timestamp()
      CYPHER
      
      tx.run(query, method_id: @time_entity.id, rights_id: @time_entity.provenance_and_rights_id)
    rescue Neo4j::Driver::Exceptions::ClientException => e
      Rails.logger.warn "Could not create rights relationship for Method #{@time_entity.id}: #{e.message}"
    end
  end
end