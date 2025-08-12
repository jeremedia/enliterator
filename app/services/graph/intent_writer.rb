# frozen_string_literal: true

module Graph
  # Service to sync IntentAndTask entities to the Neo4j graph database
  # Maps PostgreSQL IntentAndTask records to Neo4j Intent nodes
  class IntentWriter
    def initialize(intent)
      @intent = intent
      @database_name = determine_database_name
    end

    def sync
      Rails.logger.info "Syncing Intent #{@intent.id} to Neo4j database: #{@database_name}"
      
      driver = Graph::Connection.instance.driver
      session = driver.session(database: @database_name)
      
      session.write_transaction do |tx|
        # Create or update the Intent node
        create_or_update_node(tx)
        
        # Create rights relationship
        create_rights_relationship(tx)
      end
      
      session.close
      true
    rescue StandardError => e
      Rails.logger.error "Failed to sync Intent #{@intent.id}: #{e.message}"
      false
    ensure
      session&.close
    end
    
    private
    
    def determine_database_name
      if @intent.batch_id
        # Find the batch and get its EKN database
        batch = IngestBatch.find(@intent.batch_id)
        batch.ensure_neo4j_database_exists!
        batch.neo4j_database_name
      else
        # Fallback to default database
        'neo4j'
      end
    end
    
    def create_or_update_node(tx)
      properties = {
        id: @intent.id,
        user_goal: @intent.user_goal,
        query_text: @intent.query_text,
        presentation_preference: @intent.presentation_preference,
        outcome_signal: @intent.outcome_signal,
        success_criteria: @intent.success_criteria,
        repr_text: @intent.repr_text,
        deliverable_type: @intent.deliverable_type,
        modality: @intent.modality,
        constraints: @intent.constraints&.to_json,
        adapter_name: @intent.adapter_name,
        adapter_params: @intent.adapter_params&.to_json,
        evaluation: @intent.evaluation&.to_json,
        observed_at: @intent.observed_at.to_s,
        created_at: @intent.created_at.to_s,
        updated_at: @intent.updated_at.to_s,
        batch_id: @intent.batch_id
      }.compact
      
      query = <<~CYPHER
        MERGE (n:Intent {id: $id})
        SET n += $properties
      CYPHER
      
      tx.run(query, id: @intent.id, properties: properties)
    end
    
    def create_rights_relationship(tx)
      return unless @intent.provenance_and_rights_id
      
      # Create relationship to ProvenanceAndRights node
      query = <<~CYPHER
        MATCH (intent:Intent {id: $intent_id})
        MATCH (rights:ProvenanceAndRights {id: $rights_id})
        MERGE (intent)-[r:HAS_RIGHTS]->(rights)
        SET r.created_at = timestamp()
      CYPHER
      
      tx.run(query, intent_id: @intent.id, rights_id: @intent.provenance_and_rights_id)
    rescue Neo4j::Driver::Exceptions::ClientException => e
      Rails.logger.warn "Could not create rights relationship for Intent #{@intent.id}: #{e.message}"
    end
  end
end