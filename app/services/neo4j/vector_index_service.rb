# frozen_string_literal: true

module Neo4j
  # Service for managing vector embeddings directly in Neo4j using GenAI plugin
  # Eliminates need for separate pgvector database
  class VectorIndexService
    def initialize(database_name = nil)
      @database_name = database_name || 'neo4j'
      @driver = Graph::Connection.instance.driver
    end
    
    # Initialize provider if supported; otherwise, fall back to per-call token
    def configure_provider
      api_key = ENV['OPENAI_API_KEY']
      raise "OPENAI_API_KEY not set" unless api_key

      session = @driver.session(database: @database_name)
      # Detect availability of config procedures
      proc_check = session.run("SHOW PROCEDURES YIELD name RETURN collect(name) AS names").single
      names = (proc_check && proc_check[:names]) || []

      if names.include?('genai.config.init')
        # Newer GenAI supports global config
        session.run(<<~CYPHER, api_key: api_key)
          CALL genai.config.init({ provider: 'openai', apiKey: $api_key })
        CYPHER
        session.run("CALL genai.config.set({ provider: 'openai', model: 'text-embedding-3-small' })")
        Rails.logger.info "Configured OpenAI provider via genai.config.*"
        session.close
        return true
      end

      # No global config available; verify encodeBatch exists and works with token
      has_encode_batch = names.include?('genai.vector.encodeBatch')
      unless has_encode_batch
        Rails.logger.warn "Neo4j GenAI encodeBatch procedure not available"
        session.close
        return false
      end

      # Probe a simple embedding call with token passed inline (common in older GenAI builds)
      begin
        session.run(<<~CYPHER, text: 'hello world', token: api_key)
          CALL genai.vector.encodeBatch([$text], 'OpenAI', { token: $token, model: 'text-embedding-3-small' })
          YIELD index, vector
          RETURN size(vector) AS dims
        CYPHER
        Rails.logger.info "GenAI encodeBatch available; using per-call token"
        true
      rescue => e
        Rails.logger.warn "GenAI encodeBatch probe failed: #{e.message}"
        false
      ensure
        session&.close
      end
    end
    
    # Verify provider is configured
    def verify_provider
      session = @driver.session(database: @database_name)
      names = session.run("SHOW PROCEDURES YIELD name RETURN collect(name) AS names").single[:names] rescue []
      session.close
      {
        has_config: names.include?('genai.config.init'),
        has_encode_batch: names.include?('genai.vector.encodeBatch'),
        providers: begin
          s = @driver.session(database: @database_name)
          r = s.run("CALL genai.vector.listEncodingProviders() YIELD name RETURN collect(name) AS providers").single
          s.close
          (r && r[:providers]) || []
        rescue
          []
        end
      }
    rescue => e
      Rails.logger.error "Failed to verify provider: #{e.message}"
      session&.close
      nil
    end
    
    # Create vector indexes for each pool type
    def create_indexes
      session = @driver.session(database: @database_name)
      
      pools = %w[Idea Manifest Experience Relational Evolutionary Practical 
                 Emanation ProvenanceAndRights Lexicon Intent]
      
      pools.each do |pool|
        create_pool_index(session, pool)
      end
      
      create_universal_index(session)
      session.close
      true
    rescue => e
      Rails.logger.error "Failed to create indexes: #{e.message}"
      session&.close
      false
    end
    
    def create_pool_index(session, pool_name)
      index_name = "#{pool_name.downcase}_embeddings"
      
      # Check if index exists first
      check_result = session.run("SHOW INDEXES YIELD name WHERE name = $name", name: index_name)
      
      unless check_result.has_next?
        session.run(<<~CYPHER)
          CREATE VECTOR INDEX #{index_name} IF NOT EXISTS
          FOR (n:#{pool_name})
          ON n.embedding
          OPTIONS {
            vector.dimensions: 1536,
            vector.similarity_function: 'cosine'
          }
        CYPHER
        
        Rails.logger.info "Created vector index for #{pool_name}"
      else
        Rails.logger.info "Vector index for #{pool_name} already exists"
      end
    end
    
    def create_universal_index(session)
      # Check if index exists
      check_result = session.run("SHOW INDEXES YIELD name WHERE name = 'universal_embeddings'")
      
      unless check_result.has_next?
        session.run(<<~CYPHER)
          CREATE VECTOR INDEX universal_embeddings IF NOT EXISTS
          FOR (n)
          ON n.embedding
          OPTIONS {
            vector.dimensions: 1536,
            vector.similarity_function: 'cosine'
          }
        CYPHER
        
        Rails.logger.info "Created universal vector index"
      else
        Rails.logger.info "Universal vector index already exists"
      end
    end
    
    # Generate embedding for text using OpenAI via Neo4j
    def generate_embedding(text)
      return nil if text.blank?
      
      session = @driver.session(database: @database_name)
      
      # Use single-text encode if available; pass token inline when needed
      query = <<~CYPHER
        CALL genai.vector.encode($text, 'OpenAI', {
          token: $token,
          model: 'text-embedding-3-small'
        }) YIELD vector
        RETURN vector AS embedding
      CYPHER

      result = session.run(query, text: text, token: ENV['OPENAI_API_KEY'])
      
      embedding = result.single[:embedding]
      session.close
      embedding
    rescue => e
      Rails.logger.error "Failed to generate embedding: #{e.message}"
      session&.close
      nil
    end
    
    # Batch generate embeddings for multiple nodes
    def generate_embeddings_for_nodes(batch_id = nil)
      session = @driver.session(database: @database_name)
      
      where_clause = batch_id ? "n.batch_id = $batch_id" : "true"
      
      result = session.run(<<~CYPHER, batch_id: batch_id)
        MATCH (n)
        WHERE #{where_clause}
        AND n.repr_text IS NOT NULL
        AND n.embedding IS NULL
        WITH n LIMIT 100
        CALL genai.vector.encode(n.repr_text, {
          provider: 'openai',
          model: 'text-embedding-3-small'
        }) 
        YIELD embedding
        SET n.embedding = embedding
        RETURN count(n) as processed
      CYPHER
      
      processed = result.single[:processed]
      session.close
      processed
    rescue => e
      Rails.logger.error "Failed to generate embeddings for nodes: #{e.message}"
      session&.close
      0
    end
    
    # Test embedding storage and retrieval
    def test_embedding_storage(text)
      session = @driver.session(database: @database_name)
      
      # Generate embedding
      embedding = generate_embedding(text)
      return nil unless embedding
      
      # Store in test node
      result = session.run(<<~CYPHER, text: text, embedding: embedding)
        CREATE (test:TestNode {
          label: 'Test Embedding Node',
          repr_text: $text,
          embedding: $embedding,
          created_at: datetime()
        })
        RETURN test, size(test.embedding) as dimensions
      CYPHER
      
      node_data = result.single
      session.close
      
      {
        node_id: node_data[:test].element_id,
        dimensions: node_data[:dimensions],
        text: text
      }
    rescue => e
      Rails.logger.error "Failed to test embedding storage: #{e.message}"
      session&.close
      nil
    end
    
    # Cleanup test nodes
    def cleanup_test_nodes
      session = @driver.session(database: @database_name)
      
      result = session.run(<<~CYPHER)
        MATCH (n:TestNode)
        WITH count(n) as count
        DETACH DELETE n
        RETURN count
      CYPHER
      
      count = result.single[:count]
      session.close
      count
    rescue => e
      Rails.logger.error "Failed to cleanup test nodes: #{e.message}"
      session&.close
      0
    end
  end
end
