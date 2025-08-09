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
    # Adjusted based on actual data: most items have 3-8 entities
    MIN_CLUSTER_SIZE = 3
    MAX_CLUSTER_SIZE = 50
    OPTIMAL_CLUSTER_SIZE = 15
    
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
      
      # Use PostgreSQL to find entities grouped by extraction_item
      # Since custom_terms isn't properly loaded to Neo4j, we use PostgreSQL
      pr_by_item = ProvenanceAndRights
        .where("custom_terms ->> 'extraction_batch' = ?", @batch.id.to_s)
        .where("custom_terms ? 'extraction_item'")
        .group_by { |pr| pr.custom_terms['extraction_item'] }
      
      pr_by_item.each do |item_id, prs|
        # Get entities using these ProvenanceAndRights
        pr_ids = prs.map(&:id)
        entities = []
        
        # Collect entities from all pools
        Idea.where(provenance_and_rights_id: pr_ids).each do |e|
          entities << { 
            id: e.id, 
            label: e.label, 
            pool_type: 'Idea',
            repr_text: e.repr_text 
          }
        end
        
        Manifest.where(provenance_and_rights_id: pr_ids).each do |e|
          entities << { 
            id: e.id, 
            label: e.label, 
            pool_type: 'Manifest',
            repr_text: e.repr_text 
          }
        end
        
        Experience.where(provenance_and_rights_id: pr_ids).each do |e|
          entities << { 
            id: e.id, 
            label: e.agent_label, 
            pool_type: 'Experience',
            repr_text: e.narrative_text 
          }
        end
        
        Practical.where(provenance_and_rights_id: pr_ids).each do |e|
          entities << { 
            id: e.id, 
            label: e.goal, 
            pool_type: 'Practical',
            repr_text: e.repr_text 
          }
        end
        
        next if entities.size < MIN_CLUSTER_SIZE || entities.size > MAX_CLUSTER_SIZE
        
        clusters << {
          strategy: 'co_occurrence',
          confidence: 0.8,
          entities: entities,
          reason: "Entities from item ##{item_id}",
          item_id: item_id
        }
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
    
    # Strategy 5: Batch clustering for comprehensive coverage
    # For sparse graphs, create overlapping batches of entities
    def cluster_by_graph_structure
      clusters = []
      
      @driver.session(database: @ekn.neo4j_database_name) do |session|
        # Get all entities grouped by pool type
        query = <<~CYPHER
          MATCH (e)
          WHERE NOT e:ProvenanceAndRights
            AND NOT e:Lexicon
          RETURN labels(e)[0] as pool, collect(e)[0..200] as entities
        CYPHER
        
        result = session.run(query)
        
        result.each do |record|
          pool = record['pool']
          all_entities = record['entities'].map { |e| extract_entity_data(e) }
          
          # Create batches of 20-30 entities for this pool
          batch_size = 25
          all_entities.each_slice(batch_size).with_index do |batch, index|
            next if batch.size < MIN_CLUSTER_SIZE
            
            clusters << {
              strategy: 'structural',
              context: "#{pool} batch #{index + 1}",
              entities: batch,
              confidence: 0.7  # Lower confidence for arbitrary batches
            }
          end
        end
        
        # Also create mixed-pool clusters
        mixed_query = <<~CYPHER
          MATCH (idea:Idea)
          WITH collect(idea)[0..30] as ideas
          MATCH (practical:Practical)
          WITH ideas, collect(practical)[0..30] as practicals
          MATCH (exp:Experience)
          WITH ideas, practicals, collect(exp)[0..10] as experiences
          RETURN ideas + practicals + experiences as mixed
        CYPHER
        
        mixed_result = session.run(mixed_query)
        mixed_result.each do |record|
          entities = record['mixed'].compact.map { |e| extract_entity_data(e) }
          
          if entities.size >= MIN_CLUSTER_SIZE
            clusters << {
              strategy: 'structural',
              context: "Mixed pool cluster",
              entities: entities[0..MAX_CLUSTER_SIZE-1],
              confidence: 0.8
            }
          end
        end
      end
      
      clusters
    end
    
    # Merge results from multiple clustering strategies
    def merge_clustering_strategies
      all_clusters = []
      
      # Run each strategy (reorder to put working ones first)
      [:co_occurrence, :structural, :proximity, :lexical].each do |strategy|
        begin
          # Handle the naming mismatch for structural
          method_name = strategy == :structural ? :cluster_by_graph_structure : "cluster_by_#{strategy}"
          clusters = send(method_name)
          Rails.logger.info "EntityClusterer: #{strategy} found #{clusters.size} clusters"
          all_clusters.concat(clusters) if clusters.any?
        rescue => e
          Rails.logger.warn "Clustering strategy #{strategy} failed: #{e.message}"
        end
      end
      
      Rails.logger.info "EntityClusterer: Total clusters before dedup: #{all_clusters.size}"
      
      # Deduplicate overlapping clusters
      result = deduplicate_clusters(all_clusters)
      Rails.logger.info "EntityClusterer: Total clusters after dedup: #{result.size}"
      
      result
    end
    
    # Remove duplicate and highly overlapping clusters
    def deduplicate_clusters(clusters)
      return [] if clusters.empty?
      
      # For sparse graphs, be very permissive with deduplication
      # Only remove exact duplicates or near-exact duplicates
      
      deduped = []
      seen_signatures = Set.new
      
      clusters.each do |cluster|
        entity_ids = cluster[:entities].map { |e| e[:id] }.sort
        
        # Create a signature for this cluster
        signature = "#{cluster[:strategy]}_#{entity_ids.join('_')}"
        
        # Only skip if we've seen this exact cluster before
        unless seen_signatures.include?(signature)
          deduped << cluster
          seen_signatures.add(signature)
        end
      end
      
      # Return all unique clusters, sorted by size (larger first) then confidence
      deduped.sort_by { |c| [-c[:entities].size, -c[:confidence]] }
    end
    
    # Extract entity data from Neo4j node
    def extract_entity_data(node)
      pool = node.labels.first.to_s
      
      # Get the appropriate label based on pool type
      label = case pool
              when 'Idea', 'Manifest'
                node['label']
              when 'Practical'
                node['goal']
              when 'Experience'
                node['narrative_text'] || node['agent_label']
              else
                node['label'] || node['title'] || node['name']
              end
      
      # Get repr_text if available
      repr_text = node['repr_text']
      
      {
        id: node.id,
        labels: node.labels,
        pool_type: pool,
        label: label,
        repr_text: repr_text,
        properties: node.properties.slice('label', 'abstract', 'goal', 'narrative_text', 'repr_text')
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