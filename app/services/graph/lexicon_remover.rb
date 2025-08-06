# frozen_string_literal: true

module Graph
  # Service to remove lexicon entries from the Neo4j graph database
  # Supports database-per-EKN isolation
  class LexiconRemover
    def initialize(lexicon_entry, ingest_batch = nil)
      @entry = lexicon_entry
      @batch = ingest_batch
      @database_name = determine_database_name
    end

    def remove
      Rails.logger.info "Removing LexiconAndOntology #{@entry.id} from Neo4j database: #{@database_name}"
      
      driver = Graph::Connection.instance.driver
      session = driver.session(database: @database_name)
      
      session.write_transaction do |tx|
        # Delete the Lexicon node and all its relationships
        query = <<~CYPHER
          MATCH (n:Lexicon {id: $id})
          DETACH DELETE n
        CYPHER
        
        tx.run(query, id: @entry.id)
      end
      
      session.close
      true
    rescue StandardError => e
      Rails.logger.error "Failed to remove lexicon entry #{@entry.id}: #{e.message}"
      false
    ensure
      session&.close
    end
    
    private
    
    def determine_database_name
      if @batch
        @batch.neo4j_database_name
      else
        'neo4j'
      end
    end
  end
end