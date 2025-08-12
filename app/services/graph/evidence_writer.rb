# frozen_string_literal: true

module Graph
  # Service to sync Evidence entities to the Neo4j graph database
  # Maps PostgreSQL Evidence records to Neo4j Evidence nodes
  class EvidenceWriter
    def initialize(evidence)
      @evidence = evidence
      @database_name = determine_database_name
    end

    def sync
      Rails.logger.info "Syncing Evidence #{@evidence.id} to Neo4j database: #{@database_name}"
      
      driver = Graph::Connection.instance.driver
      session = driver.session(database: @database_name)
      
      session.write_transaction do |tx|
        # Create or update the Evidence node
        create_or_update_node(tx)
        
        # Create rights relationship
        create_rights_relationship(tx)
      end
      
      session.close
      true
    rescue StandardError => e
      Rails.logger.error "Failed to sync Evidence #{@evidence.id}: #{e.message}"
      false
    ensure
      session&.close
    end
    
    private
    
    def determine_database_name
      # Find EKN through entity relationships
      if @evidence.provenance_and_rights&.source_ids&.any?
        # For now, assume all entities belong to Arctic Research EKN
        # TODO: More robust EKN discovery in Phase 4
        ekn = Ekn.find_by(slug: 'arctic-research')
        if ekn && ekn.neo4j_database_exists?
          return ekn.neo4j_database_name
        end
      end
      
      # Fallback to default database
      'neo4j'
    end
    
    def create_or_update_node(tx)
      properties = {
        id: @evidence.id,
        evidence_type: @evidence.evidence_type,
        description: @evidence.description,
        source_refs: @evidence.source_refs || [],
        confidence_score: @evidence.confidence_score,
        corroboration: @evidence.corroboration,
        repr_text: @evidence.repr_text,
        observed_at: @evidence.observed_at.to_s,
        created_at: @evidence.created_at.to_s,
        updated_at: @evidence.updated_at.to_s
      }.compact
      
      query = <<~CYPHER
        MERGE (n:Evidence {id: $id})
        SET n += $properties
      CYPHER
      
      tx.run(query, id: @evidence.id, properties: properties)
    end
    
    def create_rights_relationship(tx)
      return unless @evidence.provenance_and_rights_id
      
      # Create relationship to ProvenanceAndRights node
      query = <<~CYPHER
        MATCH (evidence:Evidence {id: $evidence_id})
        MATCH (rights:ProvenanceAndRights {id: $rights_id})
        MERGE (evidence)-[r:HAS_RIGHTS]->(rights)
        SET r.created_at = timestamp()
      CYPHER
      
      tx.run(query, evidence_id: @evidence.id, rights_id: @evidence.provenance_and_rights_id)
    rescue Neo4j::Driver::Exceptions::ClientException => e
      Rails.logger.warn "Could not create rights relationship for Evidence #{@evidence.id}: #{e.message}"
    end
  end
end