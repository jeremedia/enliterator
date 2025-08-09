# frozen_string_literal: true

# PURPOSE: Stage 5.5 of the pipeline - Relationship Discovery
#
# This job runs AFTER Stage 5 (Graph Assembly) when all entities are loaded.
# It discovers relationships at the graph level using clustering to find
# meaningful cross-boundary connections.
#
# Why this approach works:
# 1. Full Context: We have all entities in the graph
# 2. Smart Clustering: We identify groups of ~30 related entities
# 3. Efficient: Only process clusters likely to have relationships
# 4. Cross-cutting: Finds relationships across items/files/modules
#
# Inputs: Completed graph with entities (no relationships yet)
# Outputs: Discovered relationships added to graph
#
module Graph
  class RelationshipDiscoveryJob < Pipeline::BaseJob
    queue_as :pipeline
    
    # Configuration
    MAX_CLUSTERS_TO_PROCESS = 50
    MAX_TOKENS_PER_CLUSTER = 5000  # Increased to handle larger structural clusters
    MIN_CONFIDENCE_THRESHOLD = 0.5
    
    def perform(pipeline_run_id)
      # BaseJob sets up @pipeline_run, @batch, @ekn via around_perform
      
      log_progress "Starting relationship discovery for EKN: #{@ekn.name}"
      
      # Initialize services
      @clusterer = Graph::EntityClusterer.new(ekn: @ekn, batch: @batch)
      @driver = Graph::Connection.instance.driver
      
      # Track metrics
      @metrics = {
        clusters_identified: 0,
        clusters_processed: 0,
        relationships_found: 0,
        relationships_created: 0,
        tokens_used: 0
      }
      
      begin
        # Step 1: Identify entity clusters
        clusters = identify_clusters
        
        # Step 2: Process each cluster to find relationships
        process_clusters(clusters)
        
        # Step 3: Load discovered relationships into graph
        load_relationships_to_graph
        
        # Step 4: Validate discovered relationships and paths
        validate_discovered_relationships
        
        # Step 5: Validate graph connectivity
        validate_graph_connectivity
        
        log_progress "✅ Relationship discovery complete"
        log_progress "   Clusters processed: #{@metrics[:clusters_processed]}"
        log_progress "   Relationships found: #{@metrics[:relationships_found]}"
        log_progress "   Relationships created: #{@metrics[:relationships_created]}"
        log_progress "   Estimated tokens used: #{@metrics[:tokens_used]}"
        
        # Update pipeline status
        update_pipeline_status
        
      rescue => e
        log_progress "Relationship discovery failed: #{e.message}", level: :error
        log_progress e.backtrace.first(5).join("\n"), level: :debug
        raise
      end
    end
    
    private
    
    def identify_clusters
      log_progress "Identifying entity clusters..."
      
      clusters = @clusterer.identify_clusters(strategy: :all)
      @metrics[:clusters_identified] = clusters.size
      
      log_progress "Found #{clusters.size} potential clusters"
      
      # Sort by confidence and limit to max
      clusters.sort_by { |c| -c[:confidence] }
              .first(MAX_CLUSTERS_TO_PROCESS)
    end
    
    def process_clusters(clusters)
      log_progress "Processing #{clusters.size} clusters for relationship discovery..."
      
      @discovered_relationships = []
      
      clusters.each_with_index do |cluster, index|
        begin
          log_progress "Processing cluster #{index + 1}/#{clusters.size} (#{cluster[:strategy]} strategy, #{cluster[:entities].size} entities)", level: :debug
          
          relationships = discover_relationships_in_cluster(cluster)
          
          if relationships.any?
            @discovered_relationships.concat(relationships)
            @metrics[:relationships_found] += relationships.size
            log_progress "  Found #{relationships.size} relationships in cluster"
          else
            log_progress "  No relationships found in cluster", level: :debug
          end
          
          @metrics[:clusters_processed] += 1
          
          # Progress indicator
          if @metrics[:clusters_processed] % 5 == 0
            log_progress "Processed #{@metrics[:clusters_processed]}/#{clusters.size} clusters..."
          end
          
        rescue => e
          log_progress "Failed to process cluster #{index + 1}: #{e.message}", level: :warn
        end
      end
    end
    
    def discover_relationships_in_cluster(cluster)
      # Prepare entities for extraction service
      entities = cluster[:entities].map do |e|
        {
          pool_type: e[:pool_type],
          label: e[:label],
          id: e[:id].to_s
        }
      end
      
      # Get source content for this cluster
      content = build_cluster_context(cluster)
      
      # Estimate tokens
      estimated_tokens = (content.length / 4) + (entities.size * 20)
      @metrics[:tokens_used] += estimated_tokens
      
      # Skip if too large
      if estimated_tokens > MAX_TOKENS_PER_CLUSTER
        log_progress "  Skipping cluster - too large (#{estimated_tokens} tokens)", level: :debug
        return []
      end
      
      # Extract relationships
      result = Pools::RelationExtractionService.new(
        content: content,
        entities: entities
      ).extract
      
      log_progress "    Extraction result: success=#{result[:success]}, relations=#{result[:relations]&.size || 0}", level: :debug
      
      return [] unless result[:success]
      
      # Filter by confidence
      relationships = result[:relations].select do |rel|
        (rel[:confidence] || 0.5) >= MIN_CONFIDENCE_THRESHOLD
      end
      
      # Add cluster context to each relationship
      relationships.map do |rel|
        rel.merge(
          cluster_strategy: cluster[:strategy],
          cluster_confidence: cluster[:confidence],
          discovery_stage: 'stage_5.5'
        )
      end
    end
    
    def build_cluster_context(cluster)
      # Build context from entity properties and any available content
      context_parts = []
      
      # Add entity descriptions
      cluster[:entities].each do |entity|
        # Entities from EntityClusterer have direct properties, not nested
        label = entity[:label]
        pool = entity[:pool_type] || entity[:labels]&.first
        context_parts << "#{pool.to_s.capitalize}: #{label}"
        
        # Add additional context if available
        if entity[:repr_text].present?
          context_parts << entity[:repr_text]
        end
      end
      
      # For structural clusters, add information about existing connections
      if cluster[:strategy] == 'structural'
        # Add note about graph structure
        context_parts << "\nThese entities are connected in the knowledge graph through existing relationships."
        context_parts << "They form a neighborhood of related concepts that likely have additional semantic connections."
      elsif cluster[:strategy] == 'co_occurrence'
        # Add note about co-occurrence
        context_parts << "\nThese entities appear together in the same source documents."
        context_parts << "Their co-occurrence suggests potential semantic relationships."
      end
      
      # Add explicit instruction for relationship discovery
      context_parts << "\nAnalyze the connections between these entities using verbs like: embodies, elicits, codifies, exemplifies, influences, necessitates, manifests_as."
      
      context_parts.join("\n\n").truncate(8000)
    end
    
    def load_relationships_to_graph
      return if @discovered_relationships.empty?
      
      log_progress "Loading #{@discovered_relationships.size} relationships to graph..."
      
      @driver.session(database: @ekn.neo4j_database_name) do |session|
        session.write_transaction do |tx|
          @discovered_relationships.each do |rel|
            begin
              create_graph_relationship(tx, rel)
              @metrics[:relationships_created] += 1
            rescue => e
              log_progress "Failed to create relationship: #{e.message}", level: :debug
              log_progress "  Backtrace: #{e.backtrace.first(3).join("\n  ")}", level: :debug
            end
          end
        end
      end
    end
    
    def create_graph_relationship(tx, rel)
      # Build the Cypher query to create relationship
      # CRITICAL: Use appropriate property for each pool type
      source_pool = rel[:source][:pool_type] || rel[:source][:pool]
      target_pool = rel[:target][:pool_type] || rel[:target][:pool]
      
      # Map pool types to their identifier properties
      source_property = case source_pool.downcase
                       when 'idea' then 'label'
                       when 'practical' then 'goal'
                       when 'experience' then 'narrative_text'
                       else 'label'  # Default fallback
                       end
      
      target_property = case target_pool.downcase
                       when 'idea' then 'label'
                       when 'practical' then 'goal'
                       when 'experience' then 'narrative_text'
                       else 'label'  # Default fallback
                       end
      
      query = <<~CYPHER
        // Find source entity by appropriate property
        MATCH (source:#{source_pool})
        WHERE source.#{source_property} = $source_label
        
        // Find target entity by appropriate property
        MATCH (target:#{target_pool})
        WHERE target.#{target_property} = $target_label
        
        // Create relationship with properties
        CREATE (source)-[r:#{rel[:verb].upcase}]->(target)
        SET r.confidence = $confidence,
            r.evidence_span = $evidence,
            r.discovery_stage = $stage,
            r.cluster_strategy = $strategy,
            r.discovered_at = datetime()
        
        RETURN r
      CYPHER
      
      params = {
        source_label: rel[:source][:label],
        target_label: rel[:target][:label],
        confidence: rel[:confidence] || 0.5,
        evidence: rel[:evidence_span],
        stage: rel[:discovery_stage],
        strategy: rel[:cluster_strategy]
      }
      
      tx.run(query, **params)
    end
    
    def validate_discovered_relationships
      log_progress "Validating discovered relationships..."
      
      validator = Graph::PathValidator.new(ekn: @ekn, batch: @batch)
      validation_result = validator.validate_all_relationships
      
      if validation_result[:valid]
        log_progress "✅ All relationships valid", level: :debug
      else
        log_progress "⚠️ Relationship validation found issues:", level: :warn
        
        validation_result[:errors].each do |error|
          log_progress "  ERROR: #{error}", level: :error
        end
        
        validation_result[:warnings].each do |warning|
          log_progress "  WARNING: #{warning}", level: :warn
        end
      end
      
      log_progress validation_result[:summary]
      
      # Store validation results
      @metrics[:validation_errors] = validation_result[:errors].size
      @metrics[:validation_warnings] = validation_result[:warnings].size
      
      # Also validate some sample paths for textization
      validate_sample_paths
    end
    
    def validate_sample_paths
      log_progress "Validating sample paths for textization...", level: :debug
      
      textizer = Graph::PathTextizer.new(ekn: @ekn)
      sample_count = 0
      
      @driver.session(database: @ekn.neo4j_database_name) do |session|
        # Get a few connected node pairs
        query = <<~CYPHER
          MATCH (n1)-[]->(n2)
          WHERE NOT n1:ProvenanceAndRights AND NOT n1:Lexicon
            AND NOT n2:ProvenanceAndRights AND NOT n2:Lexicon
          RETURN id(n1) as source_id, id(n2) as target_id,
                 labels(n1)[0] as source_pool, n1.label as source_label,
                 labels(n2)[0] as target_pool, n2.label as target_label
          LIMIT 5
        CYPHER
        
        result = session.run(query)
        
        result.each do |record|
          source_id = record['source_id']
          target_id = record['target_id']
          
          # Try to textize the path
          begin
            textized_paths = textizer.find_and_textize_paths(source_id, target_id, max_hops: 3, limit: 1)
            
            if textized_paths && textized_paths.any?
              log_progress "  Sample path: #{textized_paths.first}", level: :debug
              sample_count += 1
            end
          rescue => e
            log_progress "  Failed to textize path: #{e.message}", level: :debug
          end
        end
      end
      
      log_progress "Successfully textized #{sample_count} sample paths", level: :debug
    end
    
    def validate_graph_connectivity
      log_progress "Validating graph connectivity..."
      
      @driver.session(database: @ekn.neo4j_database_name) do |session|
        # Check connectivity metrics
        metrics_query = <<~CYPHER
          MATCH (n)
          WHERE NOT n:ProvenanceAndRights
            AND NOT n:Lexicon
          WITH count(n) as total_nodes
          
          MATCH ()-[r]->()
          WHERE type(r) <> 'HAS_RIGHTS'
          WITH total_nodes, count(r) as total_relationships
          
          MATCH (isolated)
          WHERE NOT (isolated)-[]-()
            AND NOT isolated:ProvenanceAndRights
            AND NOT isolated:Lexicon
          WITH total_nodes, total_relationships, count(isolated) as isolated_nodes
          
          RETURN total_nodes, total_relationships, isolated_nodes,
                 toFloat(total_relationships) / toFloat(total_nodes) as avg_degree
        CYPHER
        
        result = session.run(metrics_query)
        metrics = result.single rescue nil
        
        if metrics
          log_progress "Graph metrics:"
          log_progress "  Total nodes: #{metrics['total_nodes']}"
          log_progress "  Total relationships: #{metrics['total_relationships']}"
          log_progress "  Isolated nodes: #{metrics['isolated_nodes']}"
          log_progress "  Average degree: #{'%.2f' % metrics['avg_degree']}"
          
          # Update batch metadata with connectivity info
          @batch.update!(
            graph_metadata: (@batch.graph_metadata || {}).merge(
              'connectivity' => {
                'total_nodes' => metrics['total_nodes'],
                'total_relationships' => metrics['total_relationships'],
                'isolated_nodes' => metrics['isolated_nodes'],
                'average_degree' => metrics['avg_degree'],
                'discovery_complete' => true
              }
            )
          )
        end
      end
    end
    
    def update_pipeline_status
      # Mark relationship discovery as complete
      @pipeline_run.update!(
        stage_metrics: (@pipeline_run.stage_metrics || {}).merge(
          'relationship_discovery' => {
            'completed_at' => Time.current,
            'metrics' => @metrics
          }
        )
      )
      
      # BaseJob will handle advancing to next stage
    end
    
    def collect_stage_metrics
      @metrics
    end
  end
end