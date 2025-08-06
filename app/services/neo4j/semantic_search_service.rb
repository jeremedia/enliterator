# frozen_string_literal: true

module Neo4j
  # Service for semantic and hybrid search using Neo4j GenAI embeddings
  class SemanticSearchService
    def initialize(database_name = nil, batch_id = nil)
      @database_name = database_name || 'neo4j'
      @batch_id = batch_id
      @driver = Graph::Connection.instance.driver
      @vector_service = VectorIndexService.new(@database_name)
    end
    
    # Pure semantic search using vector similarity
    def semantic_search(query_text, limit: 10, pool: nil)
      # Generate embedding for query
      query_embedding = @vector_service.generate_embedding(query_text)
      return [] unless query_embedding
      
      session = @driver.session(database: @database_name)
      
      # Use vector similarity search
      index_name = pool ? "#{pool.downcase}_embeddings" : "universal_embeddings"
      where_clause = @batch_id ? "AND node.batch_id = $batch_id" : ""
      
      result = session.run(<<~CYPHER, embedding: query_embedding, limit: limit, batch_id: @batch_id)
        CALL db.index.vector.queryNodes('#{index_name}', $limit, $embedding)
        YIELD node, score
        WHERE true #{where_clause}
        RETURN 
          node,
          score,
          labels(node) as labels,
          node.label as label,
          node.repr_text as text
        ORDER BY score DESC
      CYPHER
      
      results = result.map do |r|
        {
          node_id: r[:node].element_id,
          labels: r[:labels],
          label: r[:label],
          text: r[:text],
          score: r[:score]
        }
      end
      
      session.close
      results
    rescue => e
      Rails.logger.error "Semantic search failed: #{e.message}"
      session&.close
      []
    end
    
    # Hybrid search: combines semantic similarity with graph structure
    def hybrid_search(query_text, limit: 10, hops: 2)
      query_embedding = @vector_service.generate_embedding(query_text)
      return [] unless query_embedding
      
      session = @driver.session(database: @database_name)
      where_clause = @batch_id ? "AND semantic_node.batch_id = $batch_id" : ""
      
      result = session.run(<<~CYPHER, embedding: query_embedding, limit: limit, batch_id: @batch_id)
        // Find semantically similar nodes
        CALL db.index.vector.queryNodes('universal_embeddings', $limit, $embedding)
        YIELD node as semantic_node, score as semantic_score
        WHERE true #{where_clause}
        
        // Also find structurally connected nodes within #{hops} hops
        OPTIONAL MATCH path = (semantic_node)-[*1..#{hops}]-(connected)
        WHERE connected.embedding IS NOT NULL
        
        // Calculate combined score (semantic + structural proximity)
        WITH semantic_node, 
             semantic_score,
             collect(DISTINCT connected) as connected_nodes,
             collect(path) as paths
        
        // Calculate structural bonus based on shortest path
        WITH semantic_node,
             semantic_score,
             connected_nodes,
             CASE 
               WHEN size(paths) > 0 
               THEN reduce(min = 999, p in paths | 
                    CASE WHEN length(p) < min THEN length(p) ELSE min END)
               ELSE null
             END as min_path_length
        
        RETURN 
          semantic_node as node,
          labels(semantic_node) as labels,
          semantic_node.label as label,
          semantic_node.repr_text as text,
          semantic_score,
          size(connected_nodes) as connected_count,
          min_path_length,
          // Combined score: semantic + structural bonus
          semantic_score + 
            CASE 
              WHEN min_path_length IS NOT NULL 
              THEN (1.0 / (min_path_length + 1.0)) * 0.3
              ELSE 0 
            END as combined_score,
          [c in connected_nodes | {
            id: c.element_id,
            label: c.label,
            pool: labels(c)[0]
          }][0..5] as sample_connections
        ORDER BY combined_score DESC
        LIMIT $limit
      CYPHER
      
      results = result.map do |r|
        {
          node_id: r[:node].element_id,
          labels: r[:labels],
          label: r[:label],
          text: r[:text],
          semantic_score: r[:semantic_score],
          combined_score: r[:combined_score],
          connected_count: r[:connected_count],
          min_path_length: r[:min_path_length],
          sample_connections: r[:sample_connections]
        }
      end
      
      session.close
      results
    rescue => e
      Rails.logger.error "Hybrid search failed: #{e.message}"
      session&.close
      []
    end
    
    # Find similar nodes to a given node
    def find_similar(node_id, limit: 5)
      session = @driver.session(database: @database_name)
      
      result = session.run(<<~CYPHER, node_id: node_id, limit: limit)
        MATCH (source)
        WHERE elementId(source) = $node_id
        
        WITH source, source.embedding as source_embedding
        WHERE source_embedding IS NOT NULL
        
        CALL db.index.vector.queryNodes('universal_embeddings', $limit + 1, source_embedding)
        YIELD node, score
        WHERE elementId(node) <> $node_id
        
        RETURN 
          node,
          labels(node) as labels,
          node.label as label,
          node.repr_text as text,
          score as similarity
        ORDER BY similarity DESC
        LIMIT $limit
      CYPHER
      
      results = result.map do |r|
        {
          node_id: r[:node].element_id,
          labels: r[:labels],
          label: r[:label],
          text: r[:text],
          similarity: r[:similarity]
        }
      end
      
      session.close
      results
    rescue => e
      Rails.logger.error "Find similar failed: #{e.message}"
      session&.close
      []
    end
    
    # Demonstration: Create sample data with embeddings
    def create_demo_data
      session = @driver.session(database: @database_name)
      
      # Create sample nodes about Enliterator concepts
      concepts = [
        { pool: 'Idea', label: 'Enliteracy', text: 'The process of making data literate by modeling it into pools of meaning with explicit flows' },
        { pool: 'Idea', label: 'Knowledge Navigator', text: 'A conversational interface that helps users explore and understand their data through natural dialogue' },
        { pool: 'Manifest', label: 'Ten Pool Canon', text: 'The foundational structure of ten pools that organize all knowledge in the system' },
        { pool: 'Experience', label: 'User Journey', text: 'The experience of transforming raw data into a literate, conversational knowledge system' },
        { pool: 'Practical', label: 'Pipeline Stages', text: 'Nine stages from intake to delivery that transform data into knowledge navigators' },
        { pool: 'Relational', label: 'Semantic Links', text: 'Connections between concepts based on meaning similarity rather than explicit relationships' },
        { pool: 'Evolutionary', label: 'Version Control', text: 'Tracking how knowledge evolves over time with proper versioning and provenance' },
        { pool: 'Emanation', label: 'Influence Patterns', text: 'How ideas spread and influence other concepts in the knowledge graph' }
      ]
      
      created_nodes = []
      
      concepts.each do |concept|
        # Generate embedding for each concept
        embedding = @vector_service.generate_embedding(concept[:text])
        
        if embedding
          result = session.run(<<~CYPHER, concept.merge(embedding: embedding))
            CREATE (n:#{concept[:pool]} {
              label: $label,
              repr_text: $text,
              embedding: $embedding,
              created_at: datetime()
            })
            RETURN elementId(n) as id
          CYPHER
          
          created_nodes << {
            id: result.single[:id],
            **concept
          }
        end
      end
      
      # Create some explicit relationships
      session.run(<<~CYPHER)
        MATCH (enliteracy:Idea {label: 'Enliteracy'})
        MATCH (navigator:Idea {label: 'Knowledge Navigator'})
        MERGE (enliteracy)-[:ENABLES]->(navigator)
        
        MATCH (canon:Manifest {label: 'Ten Pool Canon'})
        MATCH (pipeline:Practical {label: 'Pipeline Stages'})
        MERGE (canon)-[:STRUCTURES]->(pipeline)
        
        MATCH (journey:Experience {label: 'User Journey'})
        MATCH (navigator2:Idea {label: 'Knowledge Navigator'})
        MERGE (journey)-[:REALIZES]->(navigator2)
      CYPHER
      
      session.close
      
      {
        nodes_created: created_nodes.count,
        nodes: created_nodes
      }
    rescue => e
      Rails.logger.error "Failed to create demo data: #{e.message}"
      session&.close
      nil
    end
    
    # Cleanup demo data
    def cleanup_demo_data
      session = @driver.session(database: @database_name)
      
      labels = %w[Idea Manifest Experience Practical Relational Evolutionary Emanation]
      
      result = session.run(<<~CYPHER)
        MATCH (n)
        WHERE labels(n)[0] IN ['Idea', 'Manifest', 'Experience', 'Practical', 
                                'Relational', 'Evolutionary', 'Emanation']
        AND n.created_at > datetime() - duration('PT1H')
        WITH count(n) as count
        DETACH DELETE n
        RETURN count
      CYPHER
      
      count = result.single[:count]
      session.close
      count
    rescue => e
      Rails.logger.error "Failed to cleanup demo data: #{e.message}"
      session&.close
      0
    end
  end
end