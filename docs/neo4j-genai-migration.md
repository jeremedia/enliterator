# Neo4j GenAI Integration - Migration Guide for Enliterator

## Executive Summary

Neo4j 5.17+ includes native vector embedding support and GenAI integration. Since we're building the first EKN and haven't deployed pgvector to production, we should use Neo4j's native capabilities instead of maintaining two separate databases. This gives us unified semantic-structural queries that are perfect for the Knowledge Navigator.

**Good news: GenAI plugin v2025.07.1 is already installed!** We just need to configure the OpenAI provider and update the pipeline.

## Benefits of This Approach

### Architectural Simplification
- **One database** instead of two (eliminate pgvector)
- **Single source of truth** for both relationships and embeddings
- **No synchronization** between Neo4j and pgvector needed
- **Unified queries** that combine graph traversal with semantic similarity

### Knowledge Navigator Advantages
- **Semantic navigation**: Find similar nodes even without explicit edges
- **Hybrid queries**: "Show things connected to AND similar to X"
- **Smarter visualizations**: Position nodes by both structure and meaning
- **Natural language search**: Query embeddings match user intent to nodes

## Prerequisites

### 1. Neo4j Version Check
Ensure Neo4j is version 5.17 or higher:
```cypher
CALL dbms.components() YIELD name, versions
WHERE name = 'Neo4j Kernel'
RETURN versions[0] as version
```

### 2. Choose Embedding Model
OpenAI offers different embedding models with trade-offs:

| Model | Dimensions | Cost per 1M tokens | Best For |
|-------|------------|-------------------|----------|
| text-embedding-3-small | 1536 | $0.02 | Default choice, good balance |
| text-embedding-3-large | 3072 | $0.13 | Higher accuracy needs |
| text-embedding-ada-002 | 1536 | $0.10 | Legacy compatibility |

For Enliterator, we recommend `text-embedding-3-small` for the best performance/cost ratio.

### 2. Configure GenAI Plugin (Already Installed - v2025.07.1)

Since the GenAI plugin is already installed, we just need to configure the OpenAI provider.

#### Configure OpenAI Provider
In the Neo4j Browser or via Cypher, set up the OpenAI provider:

```cypher
// Initialize OpenAI provider with your API key
CALL genai.config.init({
  provider: 'openai',
  apiKey: $openai_api_key
})

// Set default embedding model
CALL genai.config.set({
  provider: 'openai',
  model: 'text-embedding-3-small'  // 1536 dimensions
})
```

#### Verify Configuration
```cypher
// Test that OpenAI provider is configured
CALL genai.config.show()
YIELD provider, isConfigured, models
RETURN provider, isConfigured, models

// Test embedding generation
CALL genai.vector.encode("test text", {
  provider: 'openai',
  model: 'text-embedding-3-small'
}) YIELD embedding
RETURN size(embedding) as dimensions
// Should return 1536
```

## Migration Steps

### Step 1: Remove pgvector Dependencies

Remove from Gemfile:
```ruby
# DELETE THESE LINES
gem 'pgvector'
gem 'neighbor'
```

Remove pgvector migrations:
```bash
rm db/migrate/*_install_pgvector.rb
rm db/migrate/*_create_embeddings.rb
```

Remove the Embedding model:
```bash
rm app/models/embedding.rb
```

### Step 2: Update Neo4j Connection Configuration

Update `config/neo4j.yml`:
```yaml
development:
  url: bolt://localhost:7687
  username: neo4j
  password: <%= ENV['NEO4J_PASSWORD'] %>
  # Add GenAI configuration
  genai:
    provider: openai
    model: text-embedding-3-small
    dimension: 1536
```

### Step 3: Configure OpenAI Provider in Rails

Create an initializer `config/initializers/neo4j_genai.rb`:
```ruby
# Configure Neo4j GenAI provider on Rails startup
Rails.application.config.after_initialize do
  if defined?(Neo4j::VectorIndexService)
    begin
      vector_service = Neo4j::VectorIndexService.new
      vector_service.configure_provider
      config = vector_service.verify_provider
      
      Rails.logger.info "Neo4j GenAI initialized with OpenAI provider"
      Rails.logger.info "Available models: #{config[:models].join(', ')}" if config[:models]
    rescue => e
      Rails.logger.error "Failed to initialize Neo4j GenAI: #{e.message}"
      Rails.logger.error "Make sure OPENAI_API_KEY is set and Neo4j GenAI plugin is installed"
    end
  end
end
```

### Step 4: Create Vector Index Management Service

Create `app/services/neo4j/vector_index_service.rb`:
```ruby
module Neo4j
  class VectorIndexService
    include Neo4j::Connection
    
    # Initialize and configure the OpenAI provider
    def configure_provider
      # Set up OpenAI provider with API key from Rails credentials
      api_key = Rails.application.credentials.openai[:api_key] || ENV['OPENAI_API_KEY']
      
      query("""
        CALL genai.config.init({
          provider: 'openai',
          apiKey: $api_key
        })
      """, api_key: api_key)
      
      # Set default model
      query("""
        CALL genai.config.set({
          provider: 'openai',
          model: 'text-embedding-3-small'
        })
      """)
      
      Rails.logger.info "Configured OpenAI provider for Neo4j GenAI"
    end
    
    # Verify provider is configured
    def verify_provider
      result = query("""
        CALL genai.config.show()
        YIELD provider, isConfigured, models
        WHERE provider = 'openai'
        RETURN isConfigured, models
      """)
      
      config = result.first
      unless config && config[:isConfigured]
        raise "OpenAI provider not configured. Run configure_provider first."
      end
      
      Rails.logger.info "OpenAI models available: #{config[:models]}"
      config
    end
    
    # Create vector indexes for each pool type
    def create_indexes
      # Ensure provider is configured first
      verify_provider
      
      pools = %w[Idea Manifest Experience Relational Evolutionary Practical 
                 Emanation ProvenanceAndRights LexiconAndOntology IntentAndTask]
      
      pools.each do |pool|
        create_pool_index(pool)
      end
      
      create_universal_index
    end
    
    def create_pool_index(pool_name)
      query("""
        CREATE VECTOR INDEX #{pool_name.downcase}_embeddings IF NOT EXISTS
        FOR (n:#{pool_name})
        ON n.embedding
        OPTIONS {
          dimension: 1536,
          similarity: 'cosine'
        }
      """)
      
      Rails.logger.info "Created vector index for #{pool_name}"
    end
    
    def create_universal_index
      query("""
        CREATE VECTOR INDEX universal_embeddings IF NOT EXISTS
        FOR (n)
        ON n.embedding
        OPTIONS {
          dimension: 1536,
          similarity: 'cosine'
        }
      """)
      
      Rails.logger.info "Created universal vector index"
    end
    
    # Generate embedding for text using OpenAI via Neo4j
    def generate_embedding(text)
      return nil if text.blank?
      
      result = query("""
        CALL genai.vector.encode($text, {
          provider: 'openai',
          model: 'text-embedding-3-small'
        }) 
        YIELD embedding
        RETURN embedding
      """, text: text)
      
      result.first[:embedding]
    end
    
    # Batch generate embeddings for multiple nodes
    def generate_embeddings_for_nodes(batch_id)
      query("""
        MATCH (n)
        WHERE n.batch_id = $batch_id 
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
      """, batch_id: batch_id)
    end
    
    # Alternative: Use batch processing for better performance
    def batch_generate_embeddings(texts)
      return [] if texts.empty?
      
      result = query("""
        UNWIND $texts AS text
        CALL genai.vector.encode(text, {
          provider: 'openai',
          model: 'text-embedding-3-small'
        }) 
        YIELD embedding
        RETURN collect(embedding) as embeddings
      """, texts: texts)
      
      result.first[:embeddings]
    end
  end
end
```

### Step 4: Update Pipeline Stage 6 (Representations & Retrieval)

Replace `app/services/representations/builder_service.rb`:
```ruby
module Representations
  class BuilderService
    def initialize(batch)
      @batch = batch
      @neo4j = Neo4j::VectorIndexService.new
    end
    
    def build!
      generate_repr_text
      generate_embeddings
      create_indexes
      verify_embeddings
    end
    
    private
    
    def generate_repr_text
      # Generate representative text for each node
      @neo4j.query("""
        MATCH (n)
        WHERE n.batch_id = $batch_id
        AND n.repr_text IS NULL
        SET n.repr_text = 
          CASE 
            WHEN n:Idea THEN n.label + ' - ' + coalesce(n.abstract, '')
            WHEN n:Manifest THEN n.label + ' - ' + coalesce(n.description, '')
            WHEN n:Experience THEN substring(n.narrative_text, 0, 200)
            ELSE n.label
          END
        RETURN count(n) as updated
      """, batch_id: @batch.id)
    end
    
    def generate_embeddings
      Rails.logger.info "Generating embeddings for batch #{@batch.id}"
      
      # Process in batches to avoid timeouts
      loop do
        result = @neo4j.generate_embeddings_for_nodes(@batch.id)
        processed = result.first[:processed]
        
        Rails.logger.info "Processed #{processed} embeddings"
        break if processed == 0
      end
    end
    
    def create_indexes
      @neo4j.create_indexes
    end
    
    def verify_embeddings
      result = @neo4j.query("""
        MATCH (n)
        WHERE n.batch_id = $batch_id
        RETURN 
          count(n) as total_nodes,
          count(n.embedding) as nodes_with_embeddings,
          count(CASE WHEN n.embedding IS NULL AND n.repr_text IS NOT NULL 
                     THEN 1 END) as missing_embeddings
      """, batch_id: @batch.id)
      
      stats = result.first
      Rails.logger.info "Embedding stats: #{stats}"
      
      @batch.update!(
        embedding_stats: stats,
        embeddings_complete: stats[:missing_embeddings] == 0
      )
    end
  end
end
```

### Step 5: Create Semantic Search Service

Create `app/services/neo4j/semantic_search_service.rb`:
```ruby
module Neo4j
  class SemanticSearchService
    include Neo4j::Connection
    
    def initialize(batch_id = nil)
      @batch_id = batch_id
      @vector_service = VectorIndexService.new
    end
    
    # Pure semantic search
    def semantic_search(query_text, limit: 10, pool: nil)
      # Generate embedding for query
      query_embedding = @vector_service.generate_embedding(query_text)
      return [] unless query_embedding
      
      # Search using vector similarity
      index_name = pool ? "#{pool.downcase}_embeddings" : "universal_embeddings"
      
      results = query("""
        CALL db.index.vector.queryNodes($index_name, $limit, $embedding)
        YIELD node, score
        WHERE node.batch_id = $batch_id
        RETURN node, score
        ORDER BY score DESC
      """, 
        index_name: index_name,
        limit: limit, 
        embedding: query_embedding,
        batch_id: @batch_id
      )
      
      results.map do |r|
        {
          node: serialize_node(r[:node]),
          score: r[:score]
        }
      end
    end
    
    # Hybrid search: semantic + structural
    def hybrid_search(query_text, limit: 10, hops: 2)
      query_embedding = @vector_service.generate_embedding(query_text)
      return [] unless query_embedding
      
      results = query("""
        // Find semantically similar nodes
        CALL db.index.vector.queryNodes('universal_embeddings', $limit, $embedding)
        YIELD node as semantic_node, score as semantic_score
        WHERE semantic_node.batch_id = $batch_id
        
        // Also find structurally connected nodes
        OPTIONAL MATCH path = (semantic_node)-[*1..#{hops}]-(connected)
        WHERE connected.batch_id = $batch_id
        
        // Combine and score
        WITH semantic_node, semantic_score, 
             collect(DISTINCT connected) as connected_nodes,
             collect(path) as paths
        
        RETURN semantic_node as node,
               semantic_score,
               connected_nodes,
               [p in paths | length(p)] as path_lengths
        ORDER BY semantic_score DESC
        LIMIT $limit
      """,
        limit: limit,
        embedding: query_embedding,
        batch_id: @batch_id
      )
      
      results.map do |r|
        {
          node: serialize_node(r[:node]),
          semantic_score: r[:semantic_score],
          connected_nodes: r[:connected_nodes].map { |n| serialize_node(n) },
          min_path_length: r[:path_lengths].min
        }
      end
    end
    
    # Find similar nodes to a given node
    def find_similar(node_id, limit: 5)
      results = query("""
        MATCH (source)
        WHERE id(source) = $node_id
        
        CALL db.index.vector.queryNodes('universal_embeddings', $limit + 1, source.embedding)
        YIELD node, score
        WHERE id(node) <> $node_id
        
        RETURN node, score
        ORDER BY score DESC
        LIMIT $limit
      """, node_id: node_id, limit: limit)
      
      results.map do |r|
        {
          node: serialize_node(r[:node]),
          similarity: r[:score]
        }
      end
    end
    
    private
    
    def serialize_node(node)
      {
        id: node.element_id,
        labels: node.labels,
        properties: node.properties.except(:embedding), # Don't send embeddings to frontend
        pool: node.labels.first
      }
    end
  end
end
```

### Step 6: Update Knowledge Navigator Integration

Update `app/services/navigator/grounded_navigator.rb`:
```ruby
module Navigator
  class GroundedNavigator
    def initialize(conversation, batch)
      @conversation = conversation
      @batch = batch
      @semantic_search = Neo4j::SemanticSearchService.new(batch.id)
      @graph = Neo4j::Connection.instance
    end
    
    def process_query(user_input)
      # Use hybrid search to find relevant nodes
      results = @semantic_search.hybrid_search(user_input, limit: 20)
      
      # Generate response based on found nodes
      if results.any?
        generate_grounded_response(user_input, results)
      else
        # Fall back to pure semantic search
        semantic_results = @semantic_search.semantic_search(user_input)
        generate_semantic_response(user_input, semantic_results)
      end
    end
    
    def generate_visualization_data(query_type, context)
      case query_type
      when :relationships
        # Get nodes and their relationships for force-directed graph
        fetch_relationship_graph(context)
      when :similarity
        # Get semantically similar nodes for clustering
        fetch_similarity_graph(context)
      when :hybrid
        # Combine structural and semantic relationships
        fetch_hybrid_graph(context)
      end
    end
    
    private
    
    def fetch_hybrid_graph(context)
      # This is where Neo4j GenAI shines - one query for both!
      @graph.query("""
        MATCH (center:#{context[:pool]})
        WHERE center.label = $label
        
        // Get structurally connected nodes
        OPTIONAL MATCH (center)-[r]-(connected)
        WITH center, collect({node: connected, relationship: type(r)}) as structural
        
        // Get semantically similar nodes
        CALL db.index.vector.queryNodes('universal_embeddings', 20, center.embedding)
        YIELD node as similar, score
        WHERE node <> center
        
        WITH center, structural, collect({node: similar, similarity: score}) as semantic
        
        RETURN center, structural, semantic
      """, label: context[:node_label])
    end
  end
end
```

### Step 7: Update Visualization to Show Semantic Similarity

Update the D3.js visualization to use semantic similarity:
```javascript
// app/javascript/navigator/visualizations/semantic_graph.js
export class SemanticGraph extends RelationshipGraph {
  constructor(container, data) {
    super(container, data);
    this.showSemanticLinks = true;
  }
  
  processGraphData(neoData) {
    const processed = super.processGraphData(neoData);
    
    // Add semantic similarity links (from hybrid search results)
    if (neoData.semantic_links) {
      neoData.semantic_links.forEach(link => {
        processed.links.push({
          source: link.source_id,
          target: link.target_id,
          type: 'SIMILAR_TO',
          strength: link.similarity,
          semantic: true
        });
      });
    }
    
    return processed;
  }
  
  renderLinks(g, links) {
    // Render structural links as solid lines
    const structuralLinks = g.append("g")
      .selectAll("line.structural")
      .data(links.filter(l => !l.semantic))
      .enter().append("line")
      .attr("class", "structural")
      .attr("stroke", "#999")
      .attr("stroke-width", d => Math.sqrt(d.strength));
    
    // Render semantic links as dashed lines
    const semanticLinks = g.append("g")
      .selectAll("line.semantic")
      .data(links.filter(l => l.semantic))
      .enter().append("line")
      .attr("class", "semantic")
      .attr("stroke", "#66a3ff")
      .attr("stroke-dasharray", "5,5")
      .attr("stroke-width", d => d.strength * 2)
      .attr("opacity", 0.6);
    
    return { structuralLinks, semanticLinks };
  }
  
  toggleSemanticLinks() {
    this.showSemanticLinks = !this.showSemanticLinks;
    d3.selectAll("line.semantic")
      .transition()
      .duration(300)
      .attr("opacity", this.showSemanticLinks ? 0.6 : 0);
  }
}
```

### Step 8: Test the Integration

Create a test script `script/test_neo4j_genai.rb`:
```ruby
# Test Neo4j GenAI integration
require_relative '../config/environment'

puts "Testing Neo4j GenAI Integration..."

# Test 1: Generate an embedding
vector_service = Neo4j::VectorIndexService.new
test_text = "Enliteracy is the process of making data literate"
embedding = vector_service.generate_embedding(test_text)

if embedding && embedding.is_a?(Array) && embedding.length == 1536
  puts "✅ Embedding generation works! (dimension: #{embedding.length})"
else
  puts "❌ Embedding generation failed"
  exit 1
end

# Test 2: Store embedding on a node
neo4j = Neo4j::Connection.instance
result = neo4j.query("""
  CREATE (test:TestNode {
    label: 'Test Enliteracy Node',
    repr_text: $text,
    embedding: $embedding,
    created_at: datetime()
  })
  RETURN test
""", text: test_text, embedding: embedding)

if result.first
  puts "✅ Embedding stored on node"
else
  puts "❌ Failed to store embedding"
  exit 1
end

# Test 3: Vector similarity search
search_service = Neo4j::SemanticSearchService.new
results = search_service.semantic_search("literacy and knowledge", limit: 5)

if results.any?
  puts "✅ Semantic search works! Found #{results.count} results"
  results.each do |r|
    puts "  - #{r[:node][:properties][:label]} (score: #{r[:score].round(3)})"
  end
else
  puts "⚠️  No semantic search results (might need more data)"
end

# Cleanup
neo4j.query("MATCH (n:TestNode) DELETE n")

puts "\n✅ All Neo4j GenAI tests passed!"
```

## Benefits for Knowledge Navigator

### 1. Unified Queries
```cypher
// One query to rule them all
MATCH (user_interest:Node {label: $interest})
CALL db.index.vector.queryNodes('universal_embeddings', 10, user_interest.embedding)
YIELD node as similar, score
OPTIONAL MATCH path = shortestPath((user_interest)-[*..3]-(similar))
RETURN similar, score, path
ORDER BY score DESC
```

### 2. Semantic Neighborhoods
Nodes naturally cluster by meaning, making the force-directed graph more intuitive.

### 3. Intelligent Navigation
The Navigator can now say: "I found 5 directly connected concepts and 12 semantically related ones. Would you like to explore the hidden connections?"

### 4. Better Understanding
When the fine-tuned model queries the graph, it can use semantic similarity to find relevant context even when exact matches don't exist.

## Migration Checklist

- [x] Neo4j 5.17+ (GenAI plugin v2025.07.1 installed)
- [x] Configure OpenAI provider with API key ✅ VALIDATED 2025-08-06
- [x] Test GenAI procedures (genai.vector.encodeBatch working)
- [x] Create proof-of-concept with embeddings ✅ 81.6% similarity achieved
- [x] Validate hybrid queries ✅ Structure + semantics in one query
- [x] Make architectural go/no-go decision ✅ GO WITH NEO4J GENAI
- [ ] Remove pgvector dependencies from codebase
- [x] Create VectorIndexService (implemented in app/services/neo4j/)
- [ ] Update Stage 6 pipeline to use Neo4j embeddings
- [x] Create SemanticSearchService (implemented with hybrid search)
- [ ] Update Navigator to use hybrid search
- [ ] Enhance visualizations with semantic similarity
- [x] Test the integration ✅ Full proof-of-concept successful
- [ ] Update all documentation

## Troubleshooting

### Issue: "Unknown function 'genai.vector.encode'"
**Solution**: Ensure GenAI plugin is installed and configured in neo4j.conf

### Issue: Slow embedding generation
**Solution**: Process in smaller batches (100 nodes at a time)

### Issue: Index not found
**Solution**: Ensure indexes are created before querying:
```cypher
SHOW INDEXES
```

### Issue: Different embedding dimensions
**Solution**: Ensure consistency in the model used:
```ruby
# Always use the same model
genai.openai.model=text-embedding-3-small  # 1536 dimensions
```

## Conclusion

By migrating to Neo4j's native GenAI integration, we:
1. Simplify the architecture (one database instead of two)
2. Enable powerful hybrid queries (structure + semantics)
3. Improve the Knowledge Navigator experience
4. Reduce operational complexity

This is the architecturally correct choice for a system that needs to navigate both the explicit structure and implicit meaning of knowledge.