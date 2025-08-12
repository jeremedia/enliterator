# frozen_string_literal: true

module Graph
  # Service to sync Character entities to the Neo4j graph database as Actor nodes
  # Maps PostgreSQL Character records to Neo4j Actor nodes (Ten Pool Canon)
  class ActorWriter
    def initialize(character)
      @character = character
      @database_name = determine_database_name
    end

    def sync
      Rails.logger.info "Syncing Character #{@character.id} as Actor to Neo4j database: #{@database_name}"
      
      driver = Graph::Connection.instance.driver
      session = driver.session(database: @database_name)
      
      session.write_transaction do |tx|
        # Create or update the Actor node (mapping Character -> Actor)
        create_or_update_node(tx)
        
        # Create rights relationship
        create_rights_relationship(tx)
      end
      
      session.close
      true
    rescue StandardError => e
      Rails.logger.error "Failed to sync Character #{@character.id} as Actor: #{e.message}"
      false
    ensure
      session&.close
    end
    
    private
    
    def determine_database_name
      if @character.batch_id
        # Find the batch and get its EKN database
        batch = IngestBatch.find(@character.batch_id)
        batch.ensure_neo4j_database_exists!
        batch.neo4j_database_name
      else
        # Fallback to default database
        'neo4j'
      end
    end
    
    def create_or_update_node(tx)
      properties = {
        id: @character.id,
        label: @character.label,
        title: @character.title,
        role_type: @character.role_type,
        biography: @character.biography,
        affiliations: @character.affiliations || [],
        contact_info: @character.contact_info&.to_json,
        repr_text: @character.repr_text,
        valid_time_start: @character.valid_time_start.to_s,
        valid_time_end: @character.valid_time_end&.to_s,
        created_at: @character.created_at.to_s,
        updated_at: @character.updated_at.to_s,
        batch_id: @character.batch_id,
        # Map Character fields to Actor pool semantics
        actor_name: @character.label,
        actor_role: @character.role_type,
        actor_bio: @character.biography
      }.compact
      
      query = <<~CYPHER
        MERGE (n:Actor {id: $id})
        SET n += $properties
      CYPHER
      
      tx.run(query, id: @character.id, properties: properties)
    end
    
    def create_rights_relationship(tx)
      return unless @character.provenance_and_rights_id
      
      # Create relationship to ProvenanceAndRights node
      query = <<~CYPHER
        MATCH (actor:Actor {id: $actor_id})
        MATCH (rights:ProvenanceAndRights {id: $rights_id})
        MERGE (actor)-[r:HAS_RIGHTS]->(rights)
        SET r.created_at = timestamp()
      CYPHER
      
      tx.run(query, actor_id: @character.id, rights_id: @character.provenance_and_rights_id)
    rescue Neo4j::Driver::Exceptions::ClientException => e
      Rails.logger.warn "Could not create rights relationship for Actor #{@character.id}: #{e.message}"
    end
  end
end