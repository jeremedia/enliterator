# frozen_string_literal: true

module Graph
  # Service to sync Manifest entities to the Neo4j graph database
  # Maps PostgreSQL Manifest records to Neo4j Manifest nodes
  class ManifestWriter
    def initialize(manifest)
      @manifest = manifest
      @database_name = determine_database_name
    end

    def sync
      Rails.logger.info "Syncing Manifest #{@manifest.id} to Neo4j database: #{@database_name}"
      
      driver = Graph::Connection.instance.driver
      session = driver.session(database: @database_name)
      
      session.write_transaction do |tx|
        # Create or update the Manifest node
        create_or_update_node(tx)
        
        # Create rights relationship
        create_rights_relationship(tx)
      end
      
      session.close
      true
    rescue StandardError => e
      Rails.logger.error "Failed to sync Manifest #{@manifest.id}: #{e.message}"
      false
    ensure
      session&.close
    end
    
    private
    
    def determine_database_name
      if @manifest.batch_id
        # Find the batch and get its EKN database
        batch = IngestBatch.find(@manifest.batch_id)
        batch.ensure_neo4j_database_exists!
        batch.neo4j_database_name
      else
        # Fallback to default database
        'neo4j'
      end
    end
    
    def create_or_update_node(tx)
      properties = {
        id: @manifest.id,
        label: @manifest.label,
        manifest_type: @manifest.manifest_type,
        components: @manifest.components || [],
        time_bounds: @manifest.time_bounds&.to_json,
        spatial_ref: @manifest.spatial_ref,
        repr_text: @manifest.repr_text,
        valid_time_start: @manifest.valid_time_start.to_s,
        valid_time_end: @manifest.valid_time_end&.to_s,
        created_at: @manifest.created_at.to_s,
        updated_at: @manifest.updated_at.to_s,
        batch_id: @manifest.batch_id
      }.compact
      
      query = <<~CYPHER
        MERGE (n:Manifest {id: $id})
        SET n += $properties
      CYPHER
      
      tx.run(query, id: @manifest.id, properties: properties)
    end
    
    def create_rights_relationship(tx)
      return unless @manifest.provenance_and_rights_id
      
      # Create relationship to ProvenanceAndRights node
      query = <<~CYPHER
        MATCH (manifest:Manifest {id: $manifest_id})
        MATCH (rights:ProvenanceAndRights {id: $rights_id})
        MERGE (manifest)-[r:HAS_RIGHTS]->(rights)
        SET r.created_at = timestamp()
      CYPHER
      
      tx.run(query, manifest_id: @manifest.id, rights_id: @manifest.provenance_and_rights_id)
    rescue Neo4j::Driver::Exceptions::ClientException => e
      Rails.logger.warn "Could not create rights relationship for Manifest #{@manifest.id}: #{e.message}"
    end
  end
end