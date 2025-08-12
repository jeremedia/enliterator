# frozen_string_literal: true

module Graph
  # Service to sync Experience entities to the Neo4j graph database
  # Maps PostgreSQL Experience records to Neo4j Experience nodes
  class ExperienceWriter
    def initialize(experience)
      @experience = experience
      @database_name = determine_database_name
    end

    def sync
      Rails.logger.info "Syncing Experience #{@experience.id} to Neo4j database: #{@database_name}"
      
      driver = Graph::Connection.instance.driver
      session = driver.session(database: @database_name)
      
      session.write_transaction do |tx|
        # Create or update the Experience node
        create_or_update_node(tx)
        
        # Create rights relationship
        create_rights_relationship(tx)
      end
      
      session.close
      true
    rescue StandardError => e
      Rails.logger.error "Failed to sync Experience #{@experience.id}: #{e.message}"
      false
    ensure
      session&.close
    end
    
    private
    
    def determine_database_name
      if @experience.batch_id
        # Find the batch and get its EKN database
        batch = IngestBatch.find(@experience.batch_id)
        batch.ensure_neo4j_database_exists!
        batch.neo4j_database_name
      else
        # Fallback to default database
        'neo4j'
      end
    end
    
    def create_or_update_node(tx)
      properties = {
        id: @experience.id,
        agent_label: @experience.agent_label,
        context: @experience.context,
        narrative_text: @experience.narrative_text,
        sentiment: @experience.sentiment,
        date: @experience.date&.to_s,
        repr_text: @experience.repr_text,
        observed_at: @experience.observed_at.to_s,
        created_at: @experience.created_at.to_s,
        updated_at: @experience.updated_at.to_s,
        batch_id: @experience.batch_id
      }.compact
      
      query = <<~CYPHER
        MERGE (n:Experience {id: $id})
        SET n += $properties
      CYPHER
      
      tx.run(query, id: @experience.id, properties: properties)
    end
    
    def create_rights_relationship(tx)
      return unless @experience.provenance_and_rights_id
      
      # Create relationship to ProvenanceAndRights node
      query = <<~CYPHER
        MATCH (experience:Experience {id: $experience_id})
        MATCH (rights:ProvenanceAndRights {id: $rights_id})
        MERGE (experience)-[r:HAS_RIGHTS]->(rights)
        SET r.created_at = timestamp()
      CYPHER
      
      tx.run(query, experience_id: @experience.id, rights_id: @experience.provenance_and_rights_id)
    rescue Neo4j::Driver::Exceptions::ClientException => e
      Rails.logger.warn "Could not create rights relationship for Experience #{@experience.id}: #{e.message}"
    end
  end
end