# Semantic search using pgvector embeddings
module Embedding
  class SearchService
    def initialize(batch_id)
      @batch_id = batch_id
    end
    
    def semantic_search(query, limit: 10)
      # Generate embedding for the query
      query_embedding = generate_embedding(query)
      return [] unless query_embedding
      
      # Search using pgvector's <-> operator for cosine distance
      results = Embedding.joins(:entity)
                        .where(entities: { batch_id: @batch_id })
                        .select(
                          "embeddings.*",
                          "entities.name as entity_name",
                          "entities.entity_type",
                          "entities.entity_id",
                          "(embeddings.vector <-> '#{format_vector(query_embedding)}') as distance"
                        )
                        .order("distance ASC")
                        .limit(limit)
      
      results.map do |r|
        {
          'entity_id' => r.entity_id,
          'entity_type' => r.entity_type,
          'entity_name' => r.entity_name,
          'content' => r.content,
          'similarity' => 1 - r.distance # Convert distance to similarity
        }
      end
    rescue => e
      Rails.logger.error "Semantic search failed: #{e.message}"
      []
    end
    
    private
    
    def generate_embedding(text)
      response = OPENAI.embeddings.create(
        model: "text-embedding-3-small",
        input: text
      )
      
      response.data.first.embedding
    rescue => e
      Rails.logger.error "Failed to generate embedding: #{e.message}"
      nil
    end
    
    def format_vector(embedding)
      "[#{embedding.join(',')}]"
    end
  end
end