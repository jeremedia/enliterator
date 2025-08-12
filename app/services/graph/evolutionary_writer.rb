# frozen_string_literal: true

module Graph
  # Service to sync Evolutionary entities to the Neo4j graph database
  # Maps PostgreSQL Evolutionary records to Neo4j Evolutionary nodes
  class EvolutionaryWriter
    def initialize(evolutionary)
      @evolutionary = evolutionary
      @database_name = determine_database_name
    end

    def sync
      Rails.logger.info "Syncing Evolutionary #{@evolutionary.id} to Neo4j database: #{@database_name}"
      
      driver = Graph::Connection.instance.driver
      session = driver.session(database: @database_name)
      
      session.write_transaction do |tx|
        # Create or update the Evolutionary node
        create_or_update_node(tx)
        
        # Create rights relationship
        create_rights_relationship(tx)
        
        # Create version relationships if applicable
        create_version_relationships(tx)
      end
      
      session.close
      true
    rescue StandardError => e
      Rails.logger.error "Failed to sync Evolutionary #{@evolutionary.id}: #{e.message}"
      false
    ensure
      session&.close
    end
    
    private
    
    def determine_database_name
      if @evolutionary.batch_id
        # Find the batch and get its EKN database
        batch = IngestBatch.find(@evolutionary.batch_id)
        batch.ensure_neo4j_database_exists!
        batch.neo4j_database_name
      else
        # Fallback to default database
        'neo4j'
      end
    end
    
    def create_or_update_node(tx)
      properties = {
        id: @evolutionary.id,
        change_note: @evolutionary.change_note,
        prior_ref_type: @evolutionary.prior_ref_type,
        prior_ref_id: @evolutionary.prior_ref_id,
        version_id: @evolutionary.version_id,
        refined_idea_id: @evolutionary.refined_idea_id,
        manifest_version_id: @evolutionary.manifest_version_id,
        repr_text: @evolutionary.repr_text,
        change_summary: @evolutionary.change_summary,
        delta_metrics: @evolutionary.delta_metrics&.to_json,
        valid_time_start: @evolutionary.valid_time_start.to_s,
        valid_time_end: @evolutionary.valid_time_end&.to_s,
        created_at: @evolutionary.created_at.to_s,
        updated_at: @evolutionary.updated_at.to_s,
        batch_id: @evolutionary.batch_id
      }.compact
      
      query = <<~CYPHER
        MERGE (n:Evolutionary {id: $id})
        SET n += $properties
      CYPHER
      
      tx.run(query, id: @evolutionary.id, properties: properties)
    end
    
    def create_rights_relationship(tx)
      return unless @evolutionary.provenance_and_rights_id
      
      # Create relationship to ProvenanceAndRights node
      query = <<~CYPHER
        MATCH (evolutionary:Evolutionary {id: $evolutionary_id})
        MATCH (rights:ProvenanceAndRights {id: $rights_id})
        MERGE (evolutionary)-[r:HAS_RIGHTS]->(rights)
        SET r.created_at = timestamp()
      CYPHER
      
      tx.run(query, evolutionary_id: @evolutionary.id, rights_id: @evolutionary.provenance_and_rights_id)
    rescue Neo4j::Driver::Exceptions::ClientException => e
      Rails.logger.warn "Could not create rights relationship for Evolutionary #{@evolutionary.id}: #{e.message}"
    end
    
    def create_version_relationships(tx)
      # Create "refines" relationship to Idea if refined_idea_id exists
      if @evolutionary.refined_idea_id
        query = <<~CYPHER
          MATCH (evolutionary:Evolutionary {id: $evolutionary_id})
          MATCH (idea:Idea {id: $idea_id})
          MERGE (evolutionary)-[r:REFINES]->(idea)
          SET r.created_at = timestamp()
        CYPHER
        
        tx.run(query, evolutionary_id: @evolutionary.id, idea_id: @evolutionary.refined_idea_id)
      end
      
      # Create "version_of" relationship to Manifest if manifest_version_id exists
      if @evolutionary.manifest_version_id
        query = <<~CYPHER
          MATCH (evolutionary:Evolutionary {id: $evolutionary_id})
          MATCH (manifest:Manifest {id: $manifest_id})
          MERGE (evolutionary)-[r:VERSION_OF]->(manifest)
          SET r.created_at = timestamp()
        CYPHER
        
        tx.run(query, evolutionary_id: @evolutionary.id, manifest_id: @evolutionary.manifest_version_id)
      end
    rescue Neo4j::Driver::Exceptions::ClientException => e
      Rails.logger.warn "Could not create version relationships for Evolutionary #{@evolutionary.id}: #{e.message}"
    end
  end
end