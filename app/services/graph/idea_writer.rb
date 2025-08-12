# frozen_string_literal: true

module Graph
  # Service to sync Idea entities to the Neo4j graph database
  # Maps PostgreSQL Idea records to Neo4j Idea nodes
  class IdeaWriter
    def initialize(idea)
      @idea = idea
      @database_name = determine_database_name
    end

    def sync
      Rails.logger.info "Syncing Idea #{@idea.id} to Neo4j database: #{@database_name}"
      
      driver = Graph::Connection.instance.driver
      session = driver.session(database: @database_name)
      
      session.write_transaction do |tx|
        # Create or update the Idea node
        create_or_update_node(tx)
        
        # Create rights relationship
        create_rights_relationship(tx)
      end
      
      session.close
      true
    rescue StandardError => e
      Rails.logger.error "Failed to sync Idea #{@idea.id}: #{e.message}"
      false
    ensure
      session&.close
    end
    
    private
    
    def determine_database_name
      # Find EKN through entity relationships
      # Ideas are created by pipeline extraction, trace back through ProvenanceAndRights
      if @idea.provenance_and_rights&.source_ids&.any?
        # Try to find IngestItem and its batch
        source_id = @idea.provenance_and_rights.source_ids.first
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
        id: @idea.id,
        label: @idea.label,
        abstract: @idea.abstract,
        principle_tags: @idea.principle_tags || [],
        authorship: @idea.authorship,
        inception_date: @idea.inception_date.to_s,
        repr_text: @idea.repr_text,
        is_canonical: @idea.is_canonical,
        valid_time_start: @idea.valid_time_start.to_s,
        valid_time_end: @idea.valid_time_end&.to_s,
        created_at: @idea.created_at.to_s,
        updated_at: @idea.updated_at.to_s
      }.compact
      
      query = <<~CYPHER
        MERGE (n:Idea {id: $id})
        SET n += $properties
      CYPHER
      
      tx.run(query, id: @idea.id, properties: properties)
    end
    
    def create_rights_relationship(tx)
      return unless @idea.provenance_and_rights_id
      
      # Create relationship to ProvenanceAndRights node
      query = <<~CYPHER
        MATCH (idea:Idea {id: $idea_id})
        MATCH (rights:ProvenanceAndRights {id: $rights_id})
        MERGE (idea)-[r:HAS_RIGHTS]->(rights)
        SET r.created_at = timestamp()
      CYPHER
      
      tx.run(query, idea_id: @idea.id, rights_id: @idea.provenance_and_rights_id)
    rescue Neo4j::Driver::Exceptions::ClientException => e
      Rails.logger.warn "Could not create rights relationship for Idea #{@idea.id}: #{e.message}"
    end
  end
end