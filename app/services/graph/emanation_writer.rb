# frozen_string_literal: true

module Graph
  # Service to sync Emanation entities to the Neo4j graph database
  # Maps PostgreSQL Emanation records to Neo4j Emanation nodes
  class EmanationWriter
    def initialize(emanation)
      @emanation = emanation
      @database_name = determine_database_name
    end

    def sync
      Rails.logger.info "Syncing Emanation #{@emanation.id} to Neo4j database: #{@database_name}"
      
      driver = Graph::Connection.instance.driver
      session = driver.session(database: @database_name)
      
      session.write_transaction do |tx|
        # Create or update the Emanation node
        create_or_update_node(tx)
        
        # Create rights relationship
        create_rights_relationship(tx)
      end
      
      session.close
      true
    rescue StandardError => e
      Rails.logger.error "Failed to sync Emanation #{@emanation.id}: #{e.message}"
      false
    ensure
      session&.close
    end
    
    private
    
    def determine_database_name
      if @emanation.batch_id
        # Find the batch and get its EKN database
        batch = IngestBatch.find(@emanation.batch_id)
        batch.ensure_neo4j_database_exists!
        batch.neo4j_database_name
      else
        # Fallback to default database
        'neo4j'
      end
    end
    
    def create_or_update_node(tx)
      properties = {
        id: @emanation.id,
        influence_type: @emanation.influence_type,
        target_context: @emanation.target_context,
        pathway: @emanation.pathway,
        evidence: @emanation.evidence,
        repr_text: @emanation.repr_text,
        valid_time_start: @emanation.valid_time_start.to_s,
        valid_time_end: @emanation.valid_time_end&.to_s,
        created_at: @emanation.created_at.to_s,
        updated_at: @emanation.updated_at.to_s,
        batch_id: @emanation.batch_id
      }.compact
      
      query = <<~CYPHER
        MERGE (n:Emanation {id: $id})
        SET n += $properties
      CYPHER
      
      tx.run(query, id: @emanation.id, properties: properties)
    end
    
    def create_rights_relationship(tx)
      return unless @emanation.provenance_and_rights_id
      
      # Create relationship to ProvenanceAndRights node
      query = <<~CYPHER
        MATCH (emanation:Emanation {id: $emanation_id})
        MATCH (rights:ProvenanceAndRights {id: $rights_id})
        MERGE (emanation)-[r:HAS_RIGHTS]->(rights)
        SET r.created_at = timestamp()
      CYPHER
      
      tx.run(query, emanation_id: @emanation.id, rights_id: @emanation.provenance_and_rights_id)
    rescue Neo4j::Driver::Exceptions::ClientException => e
      Rails.logger.warn "Could not create rights relationship for Emanation #{@emanation.id}: #{e.message}"
    end
  end
end