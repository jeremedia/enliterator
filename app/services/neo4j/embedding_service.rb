# frozen_string_literal: true

module Neo4j
  # Unified embedding service using Neo4j GenAI plugin
  # All embeddings stored directly in Neo4j nodes and relationships
  class EmbeddingService
    def initialize(batch_id = nil)
      @batch_id = batch_id
      @batch = IngestBatch.find(batch_id) if batch_id
      @database_name = @batch&.neo4j_database_name || 'neo4j'
      @driver = Graph::Connection.instance.driver
    end
    
    # Semantic search using Neo4j vector indexes or fallback to manual similarity
    def semantic_search(query, limit: 10, pools: nil)
      query_embedding = generate_embedding(query)
      return [] unless query_embedding
      
      session = @driver.session(database: @database_name)
      
      # First try with vector index if available
      begin
        results = search_with_index(session, query_embedding, limit, pools)
        return results if results.any?
      rescue => e
        Rails.logger.info "Vector index search failed, using fallback: #{e.message}"
      end
      
      # Fallback: manual cosine similarity calculation
      results = search_without_index(session, query_embedding, limit, pools)
      
      session.close
      results
    rescue => e
      Rails.logger.error "Semantic search failed: #{e.message}"
      session&.close
      []
    end
    
    def search_with_index(session, query_embedding, limit, pools)
      pool_clause = build_pool_clause(pools)
      
      cypher = <<~CYPHER
        CALL db.index.vector.queryNodes(
          'universal_embeddings',
          #{limit},
          $query_embedding
        ) YIELD node, score
        WHERE true #{pool_clause}
        RETURN 
          id(node) as entity_id,
          labels(node)[0] as entity_type,
          node.label as entity_name,
          node.repr_text as content,
          score as similarity
        ORDER BY score DESC
      CYPHER
      
      result = session.run(cypher, query_embedding: query_embedding)
      format_search_results(result)
    end
    
    def search_without_index(session, query_embedding, limit, pools)
      pool_clause = build_pool_clause(pools)
      
      # Manual cosine similarity using gds.similarity.cosine
      cypher = <<~CYPHER
        MATCH (n)
        WHERE n.embedding IS NOT NULL #{pool_clause}
        WITH n, gds.similarity.cosine(n.embedding, $query_embedding) AS similarity
        ORDER BY similarity DESC
        LIMIT #{limit}
        RETURN 
          id(n) as entity_id,
          labels(n)[0] as entity_type,
          n.label as entity_name,
          n.repr_text as content,
          similarity
      CYPHER
      
      result = session.run(cypher, query_embedding: query_embedding)
      format_search_results(result)
    end
    
    def build_pool_clause(pools)
      if pools && pools.any?
        labels = pools.map { |p| ":#{p}" }.join(" OR n")
        "AND (n#{labels})"
      else
        ""
      end
    end
    
    def format_search_results(result)
      result.map do |record|
        {
          'entity_id' => record[:entity_id],
          'entity_type' => record[:entity_type],
          'entity_name' => record[:entity_name],
          'content' => record[:content],
          'similarity' => record[:similarity]
        }
      end
    end
    
    # Generate embeddings for entities
    def generate_entity_embeddings(limit: 100)
      session = @driver.session(database: @database_name)
      
      # Find nodes needing embeddings
      where_clause = @batch_id ? "n.batch_id = $batch_id" : "true"
      
      cypher = <<~CYPHER
        MATCH (n)
        WHERE #{where_clause}
        AND n.repr_text IS NOT NULL
        AND n.embedding IS NULL
        WITH n LIMIT #{limit}
        WITH collect(n.repr_text) as texts, collect(n) as nodes
        CALL genai.vector.encodeBatch(texts, 'OpenAI', {
          token: $token,
          model: 'text-embedding-3-small'
        }) YIELD index, resource, vector
        WITH nodes[index] as node, vector
        SET node.embedding = vector
        RETURN count(node) as processed
      CYPHER
      
      params = { token: ENV['OPENAI_API_KEY'] }
      params[:batch_id] = @batch_id if @batch_id
      result = session.run(cypher, params)
      processed = result.single[:processed] || 0
      
      session.close
      Rails.logger.info "Generated embeddings for #{processed} entities"
      processed
    rescue => e
      Rails.logger.error "Failed to generate entity embeddings: #{e.message}"
      session&.close
      0
    end
    
    # Generate embeddings for paths
    def generate_path_embeddings(limit: 100)
      session = @driver.session(database: @database_name)
      
      where_clause = @batch_id ? "n.batch_id = $batch_id" : "true"
      
      # First, textize paths that don't have text
      textize_cypher = <<~CYPHER
        MATCH (n)-[r]->(m)
        WHERE #{where_clause}
        AND r.path_text IS NULL
        WITH n, r, m LIMIT #{limit}
        SET r.path_text = n.name + ' ' + type(r) + ' ' + m.name
        RETURN count(r) as textized
      CYPHER
      
      params = {}
      params[:batch_id] = @batch_id if @batch_id
      result = session.run(textize_cypher, params)
      textized = result.single[:textized] || 0
      Rails.logger.info "Textized #{textized} paths"
      
      # Generate embeddings for paths
      embed_cypher = <<~CYPHER
        MATCH ()-[r]->()
        WHERE r.path_text IS NOT NULL
        AND r.embedding IS NULL
        WITH r LIMIT #{limit}
        WITH collect(r.path_text) as texts, collect(r) as rels
        CALL genai.vector.encodeBatch(texts, 'OpenAI', {
          token: $token,
          model: 'text-embedding-3-small'
        }) YIELD index, resource, vector
        WITH rels[index] as rel, vector
        SET rel.embedding = vector
        RETURN count(rel) as processed
      CYPHER
      
      params = { token: ENV['OPENAI_API_KEY'] }
      params[:batch_id] = @batch_id if @batch_id
      result = session.run(embed_cypher, params)
      processed = result.single[:processed] || 0
      
      session.close
      Rails.logger.info "Generated embeddings for #{processed} paths"
      processed
    rescue => e
      Rails.logger.error "Failed to generate path embeddings: #{e.message}"
      session&.close
      0
    end
    
    # Build vector indexes if needed
    def build_indices
      vector_service = VectorIndexService.new(@database_name)
      vector_service.create_indexes
    end
    
    # Verify embeddings are working
    def verify_embeddings
      session = @driver.session(database: @database_name)
      
      where_clause = @batch_id ? "n.batch_id = $batch_id" : "true"
      
      cypher = <<~CYPHER
        MATCH (n)
        WHERE #{where_clause}
        AND n.embedding IS NOT NULL
        RETURN 
          count(n) as total_embeddings,
          avg(size(n.embedding)) as avg_dimensions,
          collect(DISTINCT labels(n)[0]) as pools_with_embeddings
      CYPHER
      
      params = {}
      params[:batch_id] = @batch_id if @batch_id
      result = session.run(cypher, params)
      stats = result.single
      
      session.close
      
      {
        total_embeddings: stats[:total_embeddings],
        avg_dimensions: stats[:avg_dimensions],
        pools_with_embeddings: stats[:pools_with_embeddings],
        status: stats[:total_embeddings] > 0 ? 'verified' : 'no_embeddings'
      }
    rescue => e
      Rails.logger.error "Failed to verify embeddings: #{e.message}"
      session&.close
      { status: 'error', error: e.message }
    end
    
    private
    
    def generate_embedding(text)
      return nil if text.blank?
      
      session = @driver.session(database: @database_name)
      
      result = session.run(<<~CYPHER, text: text, token: ENV['OPENAI_API_KEY'])
        CALL genai.vector.encode($text, 'OpenAI', {
          token: $token,
          model: 'text-embedding-3-small'
        }) YIELD vector
        RETURN vector
      CYPHER
      
      embedding = result.single[:vector]
      session.close
      embedding
    rescue => e
      Rails.logger.error "Failed to generate embedding: #{e.message}"
      session&.close
      nil
    end
  end
end
