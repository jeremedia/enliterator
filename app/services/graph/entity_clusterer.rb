# frozen_string_literal: true

module Graph
  # Identifies clusters of related entities for relationship discovery.
  # 
  # Instead of trying to find relationships within single items (wrong) or
  # between ALL entities (wasteful), we identify clusters of ~30-50 entities
  # that are likely to have meaningful relationships.
  #
  # Clustering strategies:
  # 1. Co-occurrence: Entities mentioned in the same items
  # 2. Proximity: Entities from the same module/directory  
  # 3. Semantic: Entities with similar embeddings (Stage 6+)
  # 4. Lexical: Entities with overlapping terms
  # 5. Structural: Entities connected through existing edges (iterative)
  #
  class EntityClusterer
    attr_reader :ekn, :batch
    
    # Target cluster size for optimal token usage
    MIN_CLUSTER_SIZE = 10
    MAX_CLUSTER_SIZE = 50
    OPTIMAL_CLUSTER_SIZE = 30
    
    def initialize(ekn:, batch: nil)
      @ekn = ekn
      @batch = batch
      @driver = Graph::Connection.instance.driver
    end
    
    def identify_clusters(strategy: :all)
      case strategy
      when :co_occurrence
        cluster_by_co_occurrence
      when :proximity
        cluster_by_proximity
      when :semantic
        cluster_by_semantic_similarity
      when :lexical
        cluster_by_lexical_overlap
      when :structural
        cluster_by_graph_structure
      when :all
        merge_clustering_strategies
      else
        raise ArgumentError, "Unknown clustering strategy: #{strategy}"
      end
    end
    
    private
    
    # Strategy 1: Co-occurrence clustering
    # Entities that appear in the same items are likely related
    def cluster_by_co_occurrence
      clusters = []
      
      @driver.session(database: @ekn.neo4j_database_name) do |session|
        query = <<~CYPHER
          // Find entities that share source items
          MATCH (e1)-[:HAS_RIGHTS]->(pr1:ProvenanceAndRights)
          WHERE pr1.custom_terms.extraction_item IS NOT NULL
          WITH e1, pr1.custom_terms.extraction_item as item_id
          
          MATCH (e2)-[:HAS_RIGHTS]->(pr2:ProvenanceAndRights)
          WHERE pr2.custom_terms.extraction_item = item_id
            AND id(e1) < id(e2)
            AND NOT e1:ProvenanceAndRights
            AND NOT e2:ProvenanceAndRights
          
          WITH e1, e2, count(*) as co_occurrences
          WHERE co_occurrences > 0
          
          // Group into clusters
          WITH collect({node1: e1, node2: e2, weight: co_occurrences}) as pairs
          
          // Use union-find to create clusters
          UNWIND pairs as pair
          WITH pair.node1 as node
          UNION
          WITH pair.node2 as node
          
          WITH collect(distinct node) as cluster_nodes
          WHERE size(cluster_nodes) >= #{MIN_CLUSTER_SIZE}
            AND size(cluster_nodes) <= #{MAX_CLUSTER_SIZE}
          
          RETURN cluster_nodes
          LIMIT 20
        CYPHER
        
        result = session.run(query)
        result.each do |record|
          cluster = extract_cluster_data(record['cluster_nodes'])
          clusters << cluster if cluster[:entities].size >= MIN_CLUSTER_SIZE
        end
      end
      
      clusters
    end
    
    # Strategy 2: Proximity clustering
    # Entities from the same module/directory (based on file paths)
    def cluster_by_proximity
      clusters = []
      
      return clusters unless @batch
      
      # Group items by directory
      items_by_dir = @batch.ingest_items.group_by do |item|
        next unless item.file_path
        File.dirname(item.file_path)
      end
      
      items_by_dir.each do |dir, items|
        next unless dir
        
        # Get entities from these items
        item_ids = items.map(&:id)
        entities = []
        
        @driver.session(database: @ekn.neo4j_database_name) do |session|
          query = <<~CYPHER
            MATCH (e)-[:HAS_RIGHTS]->(pr:ProvenanceAndRights)
            WHERE pr.custom_terms.extraction_item IN $item_ids
              AND NOT e:ProvenanceAndRights
              AND NOT e:Lexicon
            RETURN e
            LIMIT #{MAX_CLUSTER_SIZE}
          CYPHER
          
          result = session.run(query, item_ids: item_ids)
          result.each do |record|
            entities << extract_entity_data(record['e'])
          end
        end
        
        if entities.size >= MIN_CLUSTER_SIZE
          clusters << {
            strategy: 'proximity',
            context: "Directory: #{dir}",
            entities: entities,
            confidence: 0.7
          }
        end
      end
      
      clusters
    end
    
    # Strategy 3: Semantic similarity clustering
    # Requires embeddings from Stage 6
    def cluster_by_semantic_similarity
      clusters = []
      
      @driver.session(database: @ekn.neo4j_database_name) do |session|
        # Check if embeddings exist
        check_query = <<~CYPHER
          MATCH (n)
          WHERE n.embedding IS NOT NULL
          RETURN count(n) as count
        CYPHER
        
        result = session.run(check_query)
        embedding_count = result.single['count']
        
        return clusters if embedding_count == 0
        
        # Find semantically similar entities using vector similarity
        query = <<~CYPHER
          MATCH (e1)
          WHERE e1.embedding IS NOT NULL
            AND NOT e1:ProvenanceAndRights
            AND NOT e1:Lexicon
          
          WITH e1, e1.embedding as embedding1
          LIMIT 100
          
          MATCH (e2)
          WHERE e2.embedding IS NOT NULL
            AND id(e1) < id(e2)
            AND NOT e2:ProvenanceAndRights
            AND NOT e2:Lexicon
          
          WITH e1, e2,
            gds.similarity.cosine(e1.embedding, e2.embedding) as similarity
          WHERE similarity > 0.8
          
          // Group similar entities
          WITH e1, collect({node: e2, sim: similarity}) as similar
          WHERE size(similar) >= #{MIN_CLUSTER_SIZE - 1}
          
          WITH e1, similar[0..#{MAX_CLUSTER_SIZE - 1}] as top_similar
          
          RETURN e1, top_similar
          LIMIT 10
        CYPHER
        
        result = session.run(query)
        result.each do |record|
          entities = [extract_entity_data(record['e1'])]
          record['top_similar'].each do |item|
            entities << extract_entity_data(item['node'])
          end
          
          clusters << {
            strategy: 'semantic',
            context: "Embedding similarity > 0.8",
            entities: entities,
            confidence: 0.8
          }
        end
      end
      
      clusters
    end
    
    # Strategy 4: Lexical overlap clustering
    # Entities with similar names/terms
    def cluster_by_lexical_overlap
      clusters = []
      
      @driver.session(database: @ekn.neo4j_database_name) do |session|
        query = <<~CYPHER
          MATCH (e1)
          WHERE e1.label IS NOT NULL
            AND NOT e1:ProvenanceAndRights
            AND NOT e1:Lexicon
          
          WITH e1, 
            split(toLower(e1.label), ' ') as terms1
          
          MATCH (e2)
          WHERE e2.label IS NOT NULL
            AND id(e1) < id(e2)
            AND NOT e2:ProvenanceAndRights
            AND NOT e2:Lexicon
          
          WITH e1, e2, terms1,
            split(toLower(e2.label), ' ') as terms2
          
          // Calculate Jaccard similarity
          WITH e1, e2,
            size([t IN terms1 WHERE t IN terms2]) as intersection,
            size(terms1 + terms2) as union_size
          WHERE intersection > 0
          
          WITH e1, e2,
            toFloat(intersection) / toFloat(union_size) as jaccard
          WHERE jaccard > 0.3
          
          // Group by primary entity
          WITH e1, collect({node: e2, similarity: jaccard}) as similar
          WHERE size(similar) >= #{MIN_CLUSTER_SIZE - 1}
          
          RETURN e1, similar[0..#{MAX_CLUSTER_SIZE - 1}] as cluster_members
          LIMIT 15
        CYPHER
        
        result = session.run(query)
        result.each do |record|
          entities = [extract_entity_data(record['e1'])]
          record['cluster_members'].each do |member|
            entities << extract_entity_data(member['node'])
          end
          
          clusters << {
            strategy: 'lexical',
            context: "Lexical overlap (Jaccard > 0.3)",
            entities: entities,
            confidence: 0.6
          }
        end
      end
      
      clusters
    end
    
    # Strategy 5: Graph structure clustering
    # Use existing edges to find connected components
    def cluster_by_graph_structure
      clusters = []
      
      @driver.session(database: @ekn.neo4j_database_name) do |session|
        query = <<~CYPHER
          // Find weakly connected components
          MATCH (e)
          WHERE NOT e:ProvenanceAndRights
            AND NOT e:Lexicon
          
          // Get neighborhood within 2 hops
          CALL {
            WITH e
            MATCH path = (e)-[*1..2]-(neighbor)
            WHERE NOT neighbor:ProvenanceAndRights
              AND NOT neighbor:Lexicon
            RETURN collect(distinct neighbor) as neighbors
          }
          
          WITH e, neighbors
          WHERE size(neighbors) >= #{MIN_CLUSTER_SIZE - 1}
            AND size(neighbors) <= #{MAX_CLUSTER_SIZE - 1}
          
          WITH e, neighbors[0..#{MAX_CLUSTER_SIZE - 1}] as cluster
          
          RETURN e as center, cluster as members
          LIMIT 10
        CYPHER
        
        result = session.run(query)
        result.each do |record|
          entities = [extract_entity_data(record['center'])]
          record['members'].each do |member|
            entities << extract_entity_data(member)
          end
          
          clusters << {
            strategy: 'structural',
            context: "Graph neighborhood (2-hop)",
            entities: entities.uniq { |e| e[:id] },
            confidence: 0.9
          }
        end
      end
      
      clusters
    end
    
    # Merge results from multiple clustering strategies
    def merge_clustering_strategies
      all_clusters = []
      
      # Run each strategy
      [:co_occurrence, :proximity, :lexical, :structural].each do |strategy|
        begin
          clusters = send("cluster_by_#{strategy}")
          all_clusters.concat(clusters)
        rescue => e
          Rails.logger.warn "Clustering strategy #{strategy} failed: #{e.message}"
        end
      end
      
      # Deduplicate overlapping clusters
      deduplicate_clusters(all_clusters)
    end
    
    # Remove duplicate and highly overlapping clusters
    def deduplicate_clusters(clusters)
      return [] if clusters.empty?
      
      # Sort by confidence and size
      sorted = clusters.sort_by { |c| [-c[:confidence], -c[:entities].size] }
      
      deduped = []
      entity_coverage = Set.new
      
      sorted.each do |cluster|
        entity_ids = cluster[:entities].map { |e| e[:id] }
        
        # Calculate overlap with already selected clusters
        overlap = entity_ids.count { |id| entity_coverage.include?(id) }
        overlap_ratio = overlap.to_f / entity_ids.size
        
        # Include cluster if overlap is less than 50%
        if overlap_ratio < 0.5
          deduped << cluster
          entity_coverage.merge(entity_ids)
        end
      end
      
      deduped
    end
    
    # Extract entity data from Neo4j node
    def extract_entity_data(node)
      {
        id: node.id,
        labels: node.labels,
        pool_type: node.labels.first.to_s.downcase,
        label: node['label'] || node['title'] || node['name'],
        properties: node.properties.slice('label', 'abstract', 'goal', 'narrative_text')
      }
    end
    
    # Extract cluster data from nodes
    def extract_cluster_data(nodes)
      {
        strategy: 'co_occurrence',
        entities: nodes.map { |n| extract_entity_data(n) },
        confidence: 0.75
      }
    end
  end
end