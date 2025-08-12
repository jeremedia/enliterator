# frozen_string_literal: true

module Graph
  # Service to sync Symbolic entities to the Neo4j graph database as Emanation nodes
  # Maps PostgreSQL Symbolic records to Neo4j Emanation nodes (Ten Pool Canon)
  class SymbolicWriter
    def initialize(symbolic)
      @symbolic = symbolic
      @database_name = determine_database_name
    end

    def sync
      Rails.logger.info "Syncing Symbolic #{@symbolic.id} as Emanation to Neo4j database: #{@database_name}"
      
      driver = Graph::Connection.instance.driver
      session = driver.session(database: @database_name)
      
      session.write_transaction do |tx|
        # Create or update the Emanation node (mapping Symbolic -> Emanation)
        create_or_update_node(tx)
        
        # Create rights relationship
        create_rights_relationship(tx)
      end
      
      session.close
      true
    rescue StandardError => e
      Rails.logger.error "Failed to sync Symbolic #{@symbolic.id} as Emanation: #{e.message}"
      false
    ensure
      session&.close
    end
    
    private
    
    def determine_database_name
      if @symbolic.batch_id
        # Find the batch and get its EKN database
        batch = IngestBatch.find(@symbolic.batch_id)
        batch.ensure_neo4j_database_exists!
        batch.neo4j_database_name
      else
        # Fallback to default database
        'neo4j'
      end
    end
    
    def create_or_update_node(tx)
      properties = {
        id: @symbolic.id,
        label: @symbolic.label,
        symbol_type: @symbolic.symbol_type,
        meaning: @symbolic.meaning,
        cultural_context: @symbolic.cultural_context,
        repr_text: @symbolic.repr_text,
        valid_time_start: @symbolic.valid_time_start.to_s,
        valid_time_end: @symbolic.valid_time_end&.to_s,
        created_at: @symbolic.created_at.to_s,
        updated_at: @symbolic.updated_at.to_s,
        batch_id: @symbolic.batch_id,
        # Map Symbolic fields to Emanation pool semantics
        influence_type: @symbolic.symbol_type,
        target_context: @symbolic.cultural_context,
        pathway: "symbolic_influence",
        evidence: @symbolic.meaning
      }.compact
      
      query = <<~CYPHER
        MERGE (n:Emanation {id: $id})
        SET n += $properties
      CYPHER
      
      tx.run(query, id: @symbolic.id, properties: properties)
    end
    
    def create_rights_relationship(tx)
      return unless @symbolic.provenance_and_rights_id
      
      # Create relationship to ProvenanceAndRights node
      query = <<~CYPHER
        MATCH (emanation:Emanation {id: $emanation_id})
        MATCH (rights:ProvenanceAndRights {id: $rights_id})
        MERGE (emanation)-[r:HAS_RIGHTS]->(rights)
        SET r.created_at = timestamp()
      CYPHER
      
      tx.run(query, emanation_id: @symbolic.id, rights_id: @symbolic.provenance_and_rights_id)
    rescue Neo4j::Driver::Exceptions::ClientException => e
      Rails.logger.warn "Could not create rights relationship for Emanation #{@symbolic.id}: #{e.message}"
    end
  end
end