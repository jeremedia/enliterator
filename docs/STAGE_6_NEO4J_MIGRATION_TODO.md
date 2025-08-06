# Stage 6: Neo4j GenAI Migration TODO

## Immediate Actions Required

### 1. Remove pgvector Dependencies
```bash
# Remove from Gemfile
gem 'pgvector'
gem 'neighbor'

# Remove migration files
rm db/migrate/*_install_pgvector.rb
rm db/migrate/*_create_embeddings.rb

# Remove model
rm app/models/embedding.rb

# Update Gemfile.lock
bundle install
```

### 2. Update Stage 6 Pipeline Implementation

#### Replace `app/jobs/embedding/representation_job.rb`
```ruby
module Embedding
  class RepresentationJob < ApplicationJob
    def perform(ingest_batch_id)
      batch = IngestBatch.find(ingest_batch_id)
      
      # Generate repr_text for all nodes
      generate_repr_text(batch)
      
      # Generate embeddings using Neo4j GenAI
      generate_embeddings(batch)
      
      # Create vector indexes
      create_vector_indexes(batch)
      
      batch.update!(
        status: 'embeddings_completed',
        embeddings_completed_at: Time.current
      )
    end
    
    private
    
    def generate_embeddings(batch)
      api_key = ENV['OPENAI_API_KEY']
      database_name = batch.neo4j_database_name
      
      driver = Graph::Connection.instance.driver
      session = driver.session(database: database_name)
      
      # Get all nodes with repr_text
      nodes_query = <<~CYPHER
        MATCH (n)
        WHERE n.repr_text IS NOT NULL AND n.embedding IS NULL
        RETURN collect(n.repr_text) as texts, collect(elementId(n)) as ids
      CYPHER
      
      result = session.run(nodes_query)
      data = result.single
      
      texts = data[:texts]
      ids = data[:ids]
      
      # Batch encode with OpenAI
      texts.each_slice(100).with_index do |text_batch, batch_idx|
        id_batch = ids[batch_idx * 100, 100]
        
        encode_query = <<~CYPHER
          CALL genai.vector.encodeBatch($texts, 'OpenAI', {
            token: $token,
            model: 'text-embedding-3-small'
          })
          YIELD index, vector
          WITH $ids[index] as nodeId, vector
          MATCH (n) WHERE elementId(n) = nodeId
          SET n.embedding = vector
        CYPHER
        
        session.run(encode_query, texts: text_batch, ids: id_batch, token: api_key)
      end
      
      session.close
    end
    
    def create_vector_indexes(batch)
      database_name = batch.neo4j_database_name
      session = driver.session(database: database_name)
      
      # Create indexes for each pool
      pools = %w[Idea Manifest Experience Relational Evolutionary Practical Emanation]
      
      pools.each do |pool|
        index_query = <<~CYPHER
          CREATE VECTOR INDEX #{pool.downcase}_embeddings IF NOT EXISTS
          FOR (n:#{pool})
          ON n.embedding
          OPTIONS {
            indexConfig: {
              `vector.dimensions`: 1536,
              `vector.similarity_function`: 'cosine'
            }
          }
        CYPHER
        
        session.run(index_query) rescue nil # Index might exist
      end
      
      session.close
    end
  end
end
```

### 3. Update Search Services

#### Update `app/services/mcp/search_service.rb`
```ruby
def semantic_search(query_text, top_k: 10)
  # Generate embedding for query
  embedding = generate_query_embedding(query_text)
  
  # Search using Neo4j vector similarity
  query = <<~CYPHER
    CALL db.index.vector.queryNodes('universal_embeddings', $top_k, $embedding)
    YIELD node, score
    WHERE node.training_eligibility = true  # Rights-aware
    RETURN node, score, labels(node) as labels
    ORDER BY score DESC
  CYPHER
  
  session.run(query, top_k: top_k, embedding: embedding)
end

def hybrid_search(query_text, top_k: 10)
  embedding = generate_query_embedding(query_text)
  
  query = <<~CYPHER
    // Semantic similarity
    CALL db.index.vector.queryNodes('universal_embeddings', $top_k, $embedding)
    YIELD node as semantic_node, score
    
    // Graph structure
    OPTIONAL MATCH (semantic_node)-[r]-(connected)
    
    // Combined results
    RETURN semantic_node, score,
           collect(DISTINCT connected) as connections,
           score + size(connections) * 0.1 as combined_score
    ORDER BY combined_score DESC
    LIMIT $top_k
  CYPHER
  
  session.run(query, top_k: top_k, embedding: embedding)
end
```

### 4. Update Knowledge Navigator

#### Add to `app/services/navigator/grounded_navigator.rb`
```ruby
def get_visualization_data(context)
  case context[:visualization_type]
  when :semantic_graph
    # Get semantically similar nodes for clustering
    query = <<~CYPHER
      MATCH (center:#{context[:pool]} {label: $label})
      
      // Find semantically similar nodes
      CALL db.index.vector.queryNodes('#{context[:pool].downcase}_embeddings', 20, center.embedding)
      YIELD node as similar, score
      
      // Get relationships
      OPTIONAL MATCH (center)-[r]-(similar)
      
      RETURN center, 
             collect({node: similar, similarity: score, relationship: type(r)}) as neighbors
    CYPHER
    
    session.run(query, label: context[:node_label])
  end
end
```

### 5. Testing

Create test script `script/test_neo4j_embeddings.rb`:
```ruby
require_relative '../config/environment'

batch = IngestBatch.last

# Test embedding generation
Embedding::RepresentationJob.perform_now(batch.id)

# Test semantic search
service = Neo4j::SemanticSearchService.new(batch.neo4j_database_name)
results = service.semantic_search("knowledge navigation")

puts "Found #{results.count} semantically similar nodes"
results.each do |r|
  puts "  #{r[:label]} - Score: #{r[:score]}"
end

# Test hybrid search
hybrid_results = service.hybrid_search("literate data")
puts "\nHybrid search found #{hybrid_results.count} results"
```

## Benefits After Migration

1. **Simplified Architecture** - One database for everything
2. **Powerful Queries** - Combine structure and semantics
3. **Better Performance** - No cross-database joins
4. **EKN Isolation** - Embeddings isolated with graph data
5. **Semantic Visualizations** - Show meaning-based clusters

## Timeline

- Day 1: Remove pgvector, update pipeline job
- Day 2: Update search services, test with existing data
- Day 3: Enhance Knowledge Navigator visualizations
- Day 4: Full integration testing

## Success Criteria

- [ ] All pgvector code removed
- [ ] Embeddings stored in Neo4j nodes
- [ ] Vector indexes created and working
- [ ] Semantic search returns relevant results
- [ ] Hybrid queries combine structure + semantics
- [ ] Knowledge Navigator shows semantic relationships
- [ ] Performance comparable or better than pgvector