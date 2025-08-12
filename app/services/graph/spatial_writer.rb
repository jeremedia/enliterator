# frozen_string_literal: true

module Graph
  # Service to sync Space entities to the Neo4j graph database as Spatial nodes
  # Maps PostgreSQL Space records to Neo4j Spatial nodes (Ten Pool Canon)
  class SpatialWriter
    def initialize(space)
      @space = space
      @database_name = determine_database_name
    end

    def sync
      Rails.logger.info "Syncing Space #{@space.id} as Spatial to Neo4j database: #{@database_name}"
      
      driver = Graph::Connection.instance.driver
      session = driver.session(database: @database_name)
      
      session.write_transaction do |tx|
        # Create or update the Spatial node (mapping Space -> Spatial)
        create_or_update_node(tx)
        
        # Create rights relationship
        create_rights_relationship(tx)
      end
      
      session.close
      true
    rescue StandardError => e
      Rails.logger.error "Failed to sync Space #{@space.id} as Spatial: #{e.message}"
      false
    ensure
      session&.close
    end
    
    private
    
    def determine_database_name
      if @space.batch_id
        # Find the batch and get its EKN database
        batch = IngestBatch.find(@space.batch_id)
        batch.ensure_neo4j_database_exists!
        batch.neo4j_database_name
      else
        # Fallback to default database
        'neo4j'
      end
    end
    
    def create_or_update_node(tx)
      properties = {
        id: @space.id,
        label: @space.label,
        spatial_type: @space.spatial_type,
        region: @space.region,
        country: @space.country,
        latitude: @space.latitude&.to_f,
        longitude: @space.longitude&.to_f,
        description: @space.description,
        repr_text: @space.repr_text,
        valid_time_start: @space.valid_time_start.to_s,
        valid_time_end: @space.valid_time_end&.to_s,
        created_at: @space.created_at.to_s,
        updated_at: @space.updated_at.to_s,
        batch_id: @space.batch_id,
        # Map Space fields to Spatial pool semantics
        place_name: @space.label,
        place_type: @space.spatial_type,
        geographic_info: @space.description
      }.compact
      
      query = <<~CYPHER
        MERGE (n:Spatial {id: $id})
        SET n += $properties
      CYPHER
      
      tx.run(query, id: @space.id, properties: properties)
    end
    
    def create_rights_relationship(tx)
      return unless @space.provenance_and_rights_id
      
      # Create relationship to ProvenanceAndRights node
      query = <<~CYPHER
        MATCH (spatial:Spatial {id: $spatial_id})
        MATCH (rights:ProvenanceAndRights {id: $rights_id})
        MERGE (spatial)-[r:HAS_RIGHTS]->(rights)
        SET r.created_at = timestamp()
      CYPHER
      
      tx.run(query, spatial_id: @space.id, rights_id: @space.provenance_and_rights_id)
    rescue Neo4j::Driver::Exceptions::ClientException => e
      Rails.logger.warn "Could not create rights relationship for Spatial #{@space.id}: #{e.message}"
    end
  end
end