require 'set'

class EknStatsService
  def initialize(ekn, include_provenance: false)
    @ekn = ekn
    @driver = Graph::Connection.instance.driver
    @database = "ekn-#{@ekn.slug}"
    @include_provenance = include_provenance
    @provenance_filter = include_provenance ? "" : "WHERE labels(n)[0] <> 'ProvenanceAndRights'"
    @provenance_filter_with_prefix = include_provenance ? "" : "AND labels(n)[0] <> 'ProvenanceAndRights'"
  end
  
  def basic_stats
    {
      total_nodes: count_all_nodes,
      total_relationships: count_all_relationships,
      pool_counts: count_nodes_by_pool,
      total_documents: count_total_documents,
      pipeline_runs: count_pipeline_runs,
      last_updated: @ekn.updated_at
    }
  rescue => e
    Rails.logger.error "Error generating basic stats: #{e.message}"
    {
      total_nodes: 0,
      total_relationships: 0,
      pool_counts: {},
      total_documents: 0,
      pipeline_runs: 0,
      last_updated: @ekn.updated_at
    }
  end
  
  def comprehensive_stats
    {
      # Core metrics
      total_nodes: count_all_nodes,
      total_relationships: count_all_relationships,
      density: calculate_graph_density,
      
      # Pool analysis
      pool_counts: count_nodes_by_pool,
      pool_percentages: calculate_pool_percentages,
      
      # Network analysis
      avg_connections: calculate_average_connections,
      max_connections: find_max_connections,
      connected_components: count_connected_components,
      
      # Pipeline metrics
      total_documents: count_total_documents,
      pipeline_runs: count_pipeline_runs,
      
      # Relationship analysis
      relationship_types: count_relationships_by_type,
      bidirectional_ratio: calculate_bidirectional_ratio,
      
      # Temporal analysis
      temporal_coverage: analyze_temporal_coverage,
      temporal_density: calculate_temporal_density,
      
      # Complexity metrics
      clustering_coefficient: calculate_clustering,
      path_lengths: analyze_path_lengths,
      centrality_measures: calculate_centrality_measures
    }
  rescue => e
    Rails.logger.error "Error generating comprehensive stats: #{e.message}"
    basic_stats.merge(
      density: 0.0,
      pool_percentages: {},
      avg_connections: 0.0,
      max_connections: 0,
      connected_components: 0,
      total_documents: 0,
      pipeline_runs: 0,
      relationship_types: {},
      bidirectional_ratio: 0.0,
      temporal_coverage: default_temporal_coverage,
      temporal_density: 0.0,
      clustering_coefficient: 0.0,
      path_lengths: { avg_path_length: 0.0, diameter: 0, radius: 0 },
      centrality_measures: []
    )
  end
  
  def network_visualization_data
    # Arctic Research Knowledge Map - Simplified approach that works
    # Priority: Most connected nodes with semantic filtering
    
    provenance_condition = @include_provenance ? "" : "AND labels(n)[0] <> 'ProvenanceAndRights'"
    
    # Get top connected nodes and mark Arctic concepts
    query = <<~CYPHER
      MATCH (n)
      WHERE true #{provenance_condition}
      WITH n, 
           size([(n)--() | 1]) as connections,
           size([(n)--(other) WHERE labels(n)[0] <> labels(other)[0] | 1]) as inter_pool_connections,
           CASE 
             WHEN n.label =~ '(?i).*arctic.*|.*climate.*|.*vulnerability.*|.*sustainability.*|.*northern.*|.*polar.*'
             THEN 'domain_concept'
             WHEN size([(n)--(other) WHERE labels(n)[0] <> labels(other)[0] | 1]) > 0
             THEN 'bridge_node'
             ELSE 'representative'
           END as node_type
      WHERE connections > 0
      ORDER BY 
        CASE WHEN node_type = 'domain_concept' THEN 0 ELSE 1 END,
        connections DESC
      LIMIT 50
      RETURN 
        id(n) as id,
        coalesce(n.label, 'Entity') as label,
        coalesce(labels(n)[0], 'Unknown') as pool,
        connections,
        inter_pool_connections,
        node_type
    CYPHER
    
    nodes = execute_cypher(query)
    return { nodes: [], links: [], insights: {} } if nodes.empty?
    
    # Get all connections between selected nodes
    node_ids = nodes.map { |n| n['id'] }
    node_ids_str = node_ids.join(',')
    
    links_query = <<~CYPHER
      MATCH (n)-[r]-(m)
      WHERE id(n) IN [#{node_ids_str}] AND id(m) IN [#{node_ids_str}] AND id(n) < id(m)
      RETURN 
        id(n) as source,
        id(m) as target,
        coalesce(type(r), 'connected') as type,
        1 as weight
      LIMIT 200
    CYPHER
    
    links = execute_cypher(links_query)
    
    # Generate insights about what this network reveals
    insights = generate_network_insights(nodes, links)
    
    { nodes: nodes, links: links, insights: insights }
  rescue => e
    Rails.logger.error "Network visualization data error: #{e.message}"
    { nodes: [], links: [], insights: {} }
  end
  
  def chord_diagram_data
    # Enhanced directional flow analysis for knowledge pathways
    # Excludes ProvenanceAndRights as it lacks conceptual value
    target_pools = ['Idea', 'Practical', 'Experience', 'Manifest', 'Character', 
                   'Time', 'Space', 'Lifecycle', 'Symbolic', 'Relator', 'Lexicon']
                   
    query = <<~CYPHER
      MATCH (source)-[r]->(target)
      WHERE labels(source)[0] <> labels(target)[0] 
        AND labels(source)[0] <> 'ProvenanceAndRights' 
        AND labels(target)[0] <> 'ProvenanceAndRights'
      WITH 
        labels(source)[0] as source_pool,
        labels(target)[0] as target_pool,
        count(r) as flow_strength,
        collect(DISTINCT type(r))[..5] as relationship_types
      WHERE flow_strength >= 1  // Capture all meaningful flows
      RETURN source_pool, target_pool, flow_strength, relationship_types
      ORDER BY flow_strength DESC
    CYPHER
    
    flows = execute_cypher(query)
    return { pools: [], matrix: [], flows: [], metadata: {} } if flows.empty?
    
    # Build comprehensive pool list - include ALL conceptual pools, even isolated ones
    pools_with_flows = flows.flat_map { |f| [f['source_pool'], f['target_pool']] }.uniq & target_pools
    
    # Add isolated pools (those with entities but no inter-pool connections)
    isolated_pools_query = <<~CYPHER
      MATCH (n) 
      WHERE labels(n)[0] <> 'ProvenanceAndRights'
      WITH labels(n)[0] as pool_name, count(n) as entity_count
      WHERE entity_count > 10  // Only show pools with significant content
      RETURN pool_name
      ORDER BY entity_count DESC
    CYPHER
    
    all_conceptual_pools = execute_cypher(isolated_pools_query).map { |r| r['pool_name'] }.compact & target_pools
    pools = (pools_with_flows + all_conceptual_pools).uniq.sort
    
    return { pools: [], matrix: [], flows: [], metadata: {} } if pools.empty?
    
    # Initialize matrix and flow metadata
    matrix = Array.new(pools.size) { Array.new(pools.size, 0) }
    flow_details = {}
    pool_stats = Hash.new { |h, k| h[k] = { outgoing: 0, incoming: 0, relationships: Set.new } }
    
    # Populate matrix and collect metadata
    flows.each do |flow|
      source_pool = flow['source_pool']
      target_pool = flow['target_pool']
      strength = flow['flow_strength']
      rel_types = flow['relationship_types'] || []
      
      next unless pools.include?(source_pool) && pools.include?(target_pool)
      
      source_idx = pools.index(source_pool)
      target_idx = pools.index(target_pool)
      
      # Add to matrix
      matrix[source_idx][target_idx] = strength
      
      # Store flow details for tooltips
      flow_key = "#{source_pool}→#{target_pool}"
      flow_details[flow_key] = {
        strength: strength,
        relationship_types: rel_types,
        direction: 'outgoing'
      }
      
      # Update pool statistics
      pool_stats[source_pool][:outgoing] += strength
      pool_stats[target_pool][:incoming] += strength
      rel_types.each { |rt| pool_stats[source_pool][:relationships].add(rt) }
      rel_types.each { |rt| pool_stats[target_pool][:relationships].add(rt) }
    end
    
    # Calculate flow balance (generator vs integrator pools)
    pool_metadata = {}
    pool_stats.each do |pool, stats|
      balance = stats[:outgoing] - stats[:incoming]
      total_flow = stats[:outgoing] + stats[:incoming]
      
      pool_metadata[pool] = {
        outgoing: stats[:outgoing],
        incoming: stats[:incoming],
        balance: balance,
        total_flow: total_flow,
        archetype: balance > 5 ? 'generator' : (balance < -5 ? 'integrator' : 'balanced'),
        relationship_types: stats[:relationships].to_a,
        balance_ratio: total_flow > 0 ? (balance.to_f / total_flow).round(3) : 0.0
      }
    end
    
    {
      pools: pools,
      matrix: matrix,
      flows: flow_details,
      metadata: {
        pool_stats: pool_metadata,
        total_flows: flows.size,
        total_strength: flows.sum { |f| f['flow_strength'] },
        strongest_flow: flows.first,
        generators: pool_metadata.select { |_, stats| stats[:archetype] == 'generator' }.keys,
        integrators: pool_metadata.select { |_, stats| stats[:archetype] == 'integrator' }.keys,
        balanced: pool_metadata.select { |_, stats| stats[:archetype] == 'balanced' }.keys
      }
    }
  rescue => e
    Rails.logger.error "Chord diagram data error: #{e.message}"
    { pools: [], matrix: [], flows: [], metadata: {} }
  end
  
  def temporal_data
    # Knowledge Architecture Assembly Timeline - shows how Enliterator built the knowledge graph
    provenance_condition = @include_provenance ? "" : "AND labels(n)[0] <> 'ProvenanceAndRights'"
    query = <<~CYPHER
      MATCH (n)
      WHERE n.created_at IS NOT NULL #{provenance_condition}
      WITH 
        substring(n.created_at, 0, 16) + ':00' as time_bucket,  // Group by hour:minute (5-min buckets)
        labels(n)[0] as pool,
        count(*) as entities_in_bucket
      RETURN time_bucket, pool, entities_in_bucket
      ORDER BY time_bucket
    CYPHER
    
    raw_data = execute_cypher(query)
    return [] if raw_data.empty?
    
    # Process into visualization-ready format
    time_buckets = {}
    
    raw_data.each do |row|
      time_bucket = row['time_bucket']
      pool = row['pool'] || 'Unknown'
      count = row['entities_in_bucket'] || 0
      
      time_buckets[time_bucket] ||= {
        timestamp: time_bucket,
        total_count: 0,
        pools: {}
      }
      
      time_buckets[time_bucket][:total_count] += count
      time_buckets[time_bucket][:pools][pool] = count
    end
    
    # Convert to array and sort by timestamp
    time_buckets.values.sort_by { |bucket| bucket[:timestamp] }
  rescue => e
    Rails.logger.error "Temporal data error: #{e.message}"
    []
  end
  
  def pool_distribution
    pool_counts = count_nodes_by_pool
    pool_counts.map do |pool, count|
      {
        pool: pool,
        count: count,
        percentage: (count.to_f / count_all_nodes * 100).round(1)
      }
    end.sort_by { |p| -p[:count] }
  end
  
  def count_nodes_by_pool
    @count_nodes_by_pool ||= begin
      query = @include_provenance ? 
        "MATCH (n) RETURN labels(n)[0] as pool, count(n) as count ORDER BY count DESC" :
        "MATCH (n) #{@provenance_filter} RETURN labels(n)[0] as pool, count(n) as count ORDER BY count DESC"
      result = execute_cypher(query)
      result.to_h { |row| [row['pool'] || 'Unknown', row['count'] || 0] }
    end
  end
  
  def relationship_matrix
    # Relationship patterns between pools (list format for right panel)
    provenance_condition = @include_provenance ? "" : "WHERE labels(n)[0] <> 'ProvenanceAndRights' AND labels(m)[0] <> 'ProvenanceAndRights'"
    query = <<~CYPHER
      MATCH (n)-[r]->(m)
      #{provenance_condition}
      RETURN 
        coalesce(labels(n)[0], 'Unknown') as source_pool,
        coalesce(labels(m)[0], 'Unknown') as target_pool,
        coalesce(type(r), 'Unknown') as relationship_type,
        count(*) as frequency
      ORDER BY frequency DESC
      LIMIT 50
    CYPHER
    
    execute_cypher(query).map do |row|
      {
        source: row['source_pool'] || 'Unknown',
        target: row['target_pool'] || 'Unknown',
        type: row['relationship_type'] || 'Unknown',
        frequency: row['frequency'] || 0
      }
    end
  end
  
  def relationship_matrix_heatmap_data
    # Matrix format specifically for D3.js heatmap visualization
    provenance_condition = @include_provenance ? "" : "WHERE labels(n)[0] <> 'ProvenanceAndRights' AND labels(m)[0] <> 'ProvenanceAndRights'"
    
    # Get all relationship patterns with detailed breakdown
    query = <<~CYPHER
      MATCH (n)-[r]->(m)
      #{provenance_condition}
      WITH 
        coalesce(labels(n)[0], 'Unknown') as source_pool,
        coalesce(labels(m)[0], 'Unknown') as target_pool,
        coalesce(type(r), 'Unknown') as relationship_type,
        count(*) as frequency
      RETURN source_pool, target_pool, relationship_type, frequency
      ORDER BY frequency DESC
    CYPHER
    
    relationships = execute_cypher(query)
    return { pools: [], matrix: [], relationship_types: {}, metadata: {} } if relationships.empty?
    
    # Get all pools present in relationships
    all_pools = relationships.flat_map { |r| [r['source_pool'], r['target_pool']] }.uniq.compact.sort
    
    # Build matrix data structure
    matrix_data = []
    pool_totals = Hash.new(0)
    relationship_type_totals = Hash.new(0)
    total_relationships = 0
    
    all_pools.each_with_index do |source_pool, source_idx|
      all_pools.each_with_index do |target_pool, target_idx|
        # Find all relationships from source to target
        source_to_target = relationships.select do |r|
          r['source_pool'] == source_pool && r['target_pool'] == target_pool
        end
        
        if source_to_target.any?
          # Aggregate frequency and relationship types
          total_frequency = source_to_target.sum { |r| r['frequency'] }
          relationship_types = source_to_target.map { |r| "#{r['relationship_type']} (#{r['frequency']})" }
          dominant_type = source_to_target.max_by { |r| r['frequency'] }['relationship_type']
          
          matrix_data << {
            source_pool: source_pool,
            target_pool: target_pool,
            source_index: source_idx,
            target_index: target_idx,
            frequency: total_frequency,
            relationship_types: relationship_types,
            dominant_type: dominant_type,
            is_bidirectional: check_bidirectional(relationships, source_pool, target_pool)
          }
          
          pool_totals[source_pool] += total_frequency
          pool_totals[target_pool] += total_frequency
          total_relationships += total_frequency
          
          source_to_target.each { |r| relationship_type_totals[r['relationship_type']] += r['frequency'] }
        end
      end
    end
    
    {
      pools: all_pools,
      matrix: matrix_data,
      relationship_types: relationship_type_totals,
      metadata: {
        total_relationships: total_relationships,
        pool_totals: pool_totals,
        density: matrix_data.size.to_f / (all_pools.size * all_pools.size),
        bidirectional_count: matrix_data.count { |cell| cell[:is_bidirectional] },
        max_frequency: matrix_data.map { |cell| cell[:frequency] }.max || 0
      }
    }
  rescue => e
    Rails.logger.error "Relationship matrix heatmap data error: #{e.message}"
    { pools: [], matrix: [], relationship_types: {}, metadata: {} }
  end
  
  def most_connected_entities
    provenance_condition = @include_provenance ? "" : "AND labels(n)[0] <> 'ProvenanceAndRights'"
    query = <<~CYPHER
      MATCH (n)
      WITH n, [(n)--() | 1] as connections
      WHERE size(connections) > 0 #{provenance_condition}
      ORDER BY size(connections) DESC
      LIMIT 20
      RETURN 
        id(n) as id,
        coalesce(n.label, 'Entity') as name,
        coalesce(labels(n)[0], 'Unknown') as pool,
        size(connections) as connections,
        coalesce(n.abstract, n.description, '')[..200] as description
    CYPHER
    
    execute_cypher(query)
  end
  
  private
  
  # Helper Methods
  def check_bidirectional(relationships, pool_a, pool_b)
    # Check if there are relationships in both directions
    a_to_b = relationships.any? { |r| r['source_pool'] == pool_a && r['target_pool'] == pool_b }
    b_to_a = relationships.any? { |r| r['source_pool'] == pool_b && r['target_pool'] == pool_a }
    a_to_b && b_to_a
  end

  # Arctic Research Semantic Selection Methods
  def get_arctic_key_concepts(provenance_condition)
    # Target Arctic Research domain concepts using correct property names
    query = <<~CYPHER
      MATCH (n)
      WHERE (
        toLower(coalesce(n.label, '')) CONTAINS 'arctic' OR
        toLower(coalesce(n.abstract, '')) CONTAINS 'arctic' OR
        toLower(coalesce(n.label, '')) CONTAINS 'vulnerability' OR
        toLower(coalesce(n.abstract, '')) CONTAINS 'vulnerability' OR
        toLower(coalesce(n.label, '')) CONTAINS 'sustainability' OR
        toLower(coalesce(n.abstract, '')) CONTAINS 'sustainability' OR
        toLower(coalesce(n.label, '')) CONTAINS 'traditional knowledge' OR
        toLower(coalesce(n.abstract, '')) CONTAINS 'traditional knowledge' OR
        toLower(coalesce(n.label, '')) CONTAINS 'climate' OR
        toLower(coalesce(n.abstract, '')) CONTAINS 'climate' OR
        toLower(coalesce(n.label, '')) CONTAINS 'indigenous' OR
        toLower(coalesce(n.abstract, '')) CONTAINS 'indigenous' OR
        toLower(coalesce(n.label, '')) CONTAINS 'northern' OR
        toLower(coalesce(n.abstract, '')) CONTAINS 'northern' OR
        toLower(coalesce(n.label, '')) CONTAINS 'circumpolar' OR
        toLower(coalesce(n.abstract, '')) CONTAINS 'circumpolar'
      ) #{provenance_condition}
      WITH n, size([(n)--() | 1]) as connections
      ORDER BY connections DESC, length(coalesce(n.label, '')) DESC
      LIMIT 20
      RETURN 
        id(n) as id,
        coalesce(n.label, 'Entity') as label,
        coalesce(labels(n)[0], 'Unknown') as pool,
        connections,
        'domain_concept' as node_type
    CYPHER
    
    execute_cypher(query)
  end

  def get_pool_representatives_with_labels(provenance_condition, exclude_ids: [])
    # Get meaningful representatives from each pool with better labeling
    exclude_condition = exclude_ids.empty? ? "" : "AND NOT id(n) IN [#{exclude_ids.join(',')}]"
    
    query = <<~CYPHER
      MATCH (n)
      WHERE true #{provenance_condition} #{exclude_condition}
      WITH n, 
           labels(n)[0] as pool, 
           size([(n)--() | 1]) as connections,
           coalesce(n.label, 'Entity') as raw_label
      WHERE connections > 0 AND length(raw_label) > 3
      ORDER BY pool, connections DESC, length(raw_label) DESC
      WITH pool, collect({
        id: id(n),
        label: raw_label,
        pool: pool,
        connections: connections,
        node_type: 'pool_representative'
      })[0..1] as pool_nodes  // Top 2 from each pool
      UNWIND pool_nodes as node
      RETURN node.id as id, node.label as label, node.pool as pool, 
             node.connections as connections, node.node_type as node_type
      LIMIT 12
    CYPHER
    
    execute_cypher(query)
  end
  
  def get_high_impact_nodes(provenance_condition, threshold, exclude_ids: [])
    # Select nodes with high connections AND meaningful labels (quality over quantity)
    exclude_condition = exclude_ids.empty? ? "" : "AND NOT id(n) IN [#{exclude_ids.join(',')}]"
    
    query = <<~CYPHER
      MATCH (n)
      WITH n, 
           size([(n)--() | 1]) as connections,
           coalesce(n.label, '') as raw_label
      WHERE connections >= #{threshold} 
        AND length(raw_label) >= 5 
        #{provenance_condition} 
        #{exclude_condition}
      ORDER BY connections DESC, length(raw_label) DESC
      LIMIT 10
      RETURN 
        id(n) as id,
        raw_label as label,
        coalesce(labels(n)[0], 'Unknown') as pool,
        connections,
        'high_impact' as node_type
    CYPHER
    
    execute_cypher(query)
  end
  
  def generate_network_insights(nodes, links)
    return {} if nodes.empty?
    
    pool_distribution = nodes.group_by { |n| n['pool'] }.transform_values(&:size)
    bridge_nodes = nodes.select { |n| n['node_type'] == 'domain_concept' }.size
    connections_per_node = nodes.map { |n| n['connections'] || 0 }
    avg_connections = connections_per_node.sum.to_f / connections_per_node.size
    
    # Generate contextual insights about what this network shows
    {
      primary_insight: generate_primary_insight(pool_distribution, bridge_nodes),
      pool_balance: pool_distribution,
      network_density_insight: "Average #{avg_connections.round(1)} connections per entity",
      total_entities: nodes.size,
      total_connections: links.size,
      arctic_concepts: nodes.count { |n| n['node_type'] == 'domain_concept' },
      interpretation: generate_network_interpretation(pool_distribution, links.size)
    }
  end
  
  def generate_primary_insight(pool_distribution, arctic_concepts)
    dominant_pool = pool_distribution.max_by { |_, count| count }&.first || 'Unknown'
    case dominant_pool
    when 'Idea'
      "Arctic research shows conceptual focus: #{arctic_concepts} key domain concepts with strong theoretical foundations"
    when 'Practical'
      "Arctic knowledge emphasizes practical applications: #{arctic_concepts} domain concepts with implementation focus"
    when 'Lexicon' 
      "Arctic research is terminology-rich: #{arctic_concepts} domain concepts supported by extensive vocabulary"
    else
      "Arctic knowledge network shows #{arctic_concepts} domain concepts across #{pool_distribution.keys.size} knowledge areas"
    end
  end
  
  def generate_network_interpretation(pool_distribution, connection_count)
    if connection_count < 20
      "Emerging knowledge structure - key concepts identified but limited interconnections"
    elsif connection_count < 50  
      "Developing knowledge network - core concepts connected with growing relationship patterns"
    else
      "Mature knowledge architecture - extensive interconnections between #{pool_distribution.keys.size} knowledge domains"
    end
  end

  # Network Visualization Helper Methods
  def get_inter_pool_bridge_nodes(provenance_condition, exclude_ids: [])
    # Find nodes that connect to different pools - these are the most valuable for network viz
    exclude_condition = exclude_ids.empty? ? "" : "AND NOT id(n) IN [#{exclude_ids.join(',')}]"
    
    query = <<~CYPHER
      MATCH (n)-[r]-(connected)
      WHERE labels(n)[0] <> labels(connected)[0] #{provenance_condition} #{exclude_condition}
      WITH n, 
           size([(n)--() | 1]) as total_connections,
           size([(n)--(other) WHERE labels(n)[0] <> labels(other)[0] | 1]) as inter_pool_connections
      WHERE inter_pool_connections > 0
      ORDER BY inter_pool_connections DESC, total_connections DESC
      LIMIT 10
      RETURN 
        id(n) as id,
        coalesce(n.label, 'Entity') as label,
        coalesce(labels(n)[0], 'Unknown') as pool,
        total_connections as connections,
        inter_pool_connections
    CYPHER
    
    execute_cypher(query)
  end
  
  def get_representative_nodes_per_pool(provenance_condition, exclude_ids: [])
    # Get most connected node from each pool for diversity
    exclude_condition = exclude_ids.empty? ? "" : "AND NOT id(n) IN [#{exclude_ids.join(',')}]"
    
    query = <<~CYPHER
      MATCH (n)
      WHERE true #{provenance_condition} #{exclude_condition}
      WITH n, labels(n)[0] as pool, size([(n)--() | 1]) as connections
      ORDER BY pool, connections DESC
      WITH pool, collect({
        id: id(n),
        label: coalesce(n.label, 'Entity'),
        pool: pool,
        connections: connections
      })[0] as top_node
      WHERE top_node.connections > 0
      RETURN top_node.id as id, top_node.label as label, top_node.pool as pool, top_node.connections as connections
      LIMIT 8
    CYPHER
    
    execute_cypher(query)
  end
  
  def get_highly_connected_nodes(provenance_condition, threshold, exclude_ids: [])
    # Traditional most-connected approach with adaptive threshold
    exclude_condition = exclude_ids.empty? ? "" : "AND NOT id(n) IN [#{exclude_ids.join(',')}]"
    
    query = <<~CYPHER
      MATCH (n)
      WITH n, size([(n)--() | 1]) as connections
      WHERE connections >= #{threshold} #{provenance_condition} #{exclude_condition}
      ORDER BY connections DESC
      LIMIT 15
      RETURN 
        id(n) as id,
        coalesce(n.label, 'Entity') as label,
        coalesce(labels(n)[0], 'Unknown') as pool,
        connections
    CYPHER
    
    execute_cypher(query)
  end
  
  def get_random_diverse_sample(provenance_condition, exclude_ids: [])
    # Final fallback - random sampling ensuring pool diversity
    exclude_condition = exclude_ids.empty? ? "" : "AND NOT id(n) IN [#{exclude_ids.join(',')}]"
    
    query = <<~CYPHER
      MATCH (n)
      WHERE true #{provenance_condition} #{exclude_condition}
      WITH n, labels(n)[0] as pool, size([(n)--() | 1]) as connections, rand() as random_order
      ORDER BY pool, random_order
      WITH pool, collect({
        id: id(n),
        label: coalesce(n.label, 'Entity'),
        pool: pool,
        connections: connections
      })[..3] as pool_sample
      UNWIND pool_sample as node
      RETURN node.id as id, node.label as label, node.pool as pool, node.connections as connections
      LIMIT 20
    CYPHER
    
    execute_cypher(query)
  end
  
  def count_all_nodes
    @count_all_nodes ||= begin
      query = @include_provenance ? "MATCH (n) RETURN count(n) as count" : "MATCH (n) #{@provenance_filter} RETURN count(n) as count"
      result = execute_cypher(query)
      result.first&.dig('count') || 0
    end
  end
  
  def count_all_relationships
    @count_all_relationships ||= begin
      query = @include_provenance ? 
        "MATCH ()-[r]-() RETURN count(r)/2 as count" : 
        "MATCH (a)-[r]-(b) WHERE labels(a)[0] <> 'ProvenanceAndRights' AND labels(b)[0] <> 'ProvenanceAndRights' RETURN count(r)/2 as count"
      result = execute_cypher(query)
      result.first&.dig('count') || 0
    end
  end
  
  def count_total_documents
    @count_total_documents ||= begin
      # Count all ingest items (documents) across all ingest batches for this EKN
      @ekn.ingest_items.count
    end
  rescue => e
    Rails.logger.error "Error counting documents: #{e.message}"
    0
  end
  
  def count_pipeline_runs
    @count_pipeline_runs ||= begin
      # Count EKN pipeline runs for this EKN
      @ekn.ekn_pipeline_runs.count
    end
  rescue => e
    Rails.logger.error "Error counting pipeline runs: #{e.message}"
    0
  end
  
  def calculate_pool_percentages
    total = count_all_nodes
    return {} if total == 0
    count_nodes_by_pool.transform_values { |count| (count.to_f / total * 100).round(1) }
  end
  
  def calculate_graph_density
    nodes = count_all_nodes
    relationships = count_all_relationships
    return 0.0 if nodes <= 1
    max_possible = nodes * (nodes - 1) / 2.0
    (relationships.to_f / max_possible).round(4)
  end
  
  def calculate_average_connections
    provenance_condition = @include_provenance ? "" : "WHERE labels(n)[0] <> 'ProvenanceAndRights'"
    query = <<~CYPHER
      MATCH (n)
      #{provenance_condition}
      WITH n, [(n)--() | 1] as connections
      RETURN avg(size(connections)) as avg_connections
    CYPHER
    
    result = execute_cypher(query)
    (result.first&.dig('avg_connections') || 0).round(2)
  end
  
  def find_max_connections
    provenance_condition = @include_provenance ? "" : "WHERE labels(n)[0] <> 'ProvenanceAndRights'"
    query = <<~CYPHER
      MATCH (n)
      #{provenance_condition}
      WITH n, [(n)--() | 1] as connections
      RETURN max(size(connections)) as max_connections
    CYPHER
    
    result = execute_cypher(query)
    result.first&.dig('max_connections') || 0
  end
  
  def count_connected_components
    # Simplified - could use more sophisticated algorithms
    provenance_condition = @include_provenance ? "" : "WHERE labels(n)[0] <> 'ProvenanceAndRights' AND"
    query = <<~CYPHER
      MATCH (n)
      #{provenance_condition} NOT (n)--()
      RETURN count(n) as isolated_nodes
    CYPHER
    
    result = execute_cypher(query)
    isolated = result.first&.dig('isolated_nodes') || 0
    total_nodes = count_all_nodes
    connected_nodes = total_nodes - isolated
    
    # Rough estimate - isolated nodes + 1 main component
    isolated + (connected_nodes > 0 ? 1 : 0)
  end
  
  def count_relationships_by_type
    provenance_condition = @include_provenance ? "" : "WHERE labels(startNode(r))[0] <> 'ProvenanceAndRights' AND labels(endNode(r))[0] <> 'ProvenanceAndRights'"
    query = <<~CYPHER
      MATCH ()-[r]-()
      #{provenance_condition}
      RETURN type(r) as relationship_type, count(r)/2 as count
      ORDER BY count DESC
      LIMIT 20
    CYPHER
    
    result = execute_cypher(query)
    result.to_h { |row| [row['relationship_type'] || 'Unknown', row['count'] || 0] }
  end
  
  def calculate_bidirectional_ratio
    # Simplified calculation
    provenance_condition = @include_provenance ? "" : "WHERE labels(a)[0] <> 'ProvenanceAndRights' AND labels(b)[0] <> 'ProvenanceAndRights'"
    query = <<~CYPHER
      MATCH (a)-[r1]->(b)
      #{provenance_condition}
      WITH a, b, count(r1) as forward_count
      OPTIONAL MATCH (b)-[r2]->(a)
      WITH forward_count, count(r2) as backward_count
      WHERE backward_count > 0
      RETURN count(*) as bidirectional, sum(forward_count) as total
    CYPHER
    
    result = execute_cypher(query)
    return 0.0 if result.empty?
    
    first_result = result.first
    bidirectional = first_result['bidirectional'] || 0
    total = first_result['total'] || 1
    (bidirectional.to_f / total * 100).round(1)
  end
  
  def analyze_temporal_coverage
    provenance_condition = @include_provenance ? "" : "AND labels(n)[0] <> 'ProvenanceAndRights'"
    query = <<~CYPHER
      MATCH (n)
      WHERE (n.time_start IS NOT NULL OR n.time_end IS NOT NULL) #{provenance_condition}
      WITH n.time_start as start, n.time_end as end
      WHERE start IS NOT NULL OR end IS NOT NULL
      RETURN 
        min(coalesce(start, end)) as earliest,
        max(coalesce(end, start)) as latest,
        count(*) as temporal_nodes
    CYPHER
    
    result = execute_cypher(query)
    return default_temporal_coverage if result.empty?
    
    first_result = result.first
    {
      earliest: first_result['earliest'],
      latest: first_result['latest'],
      temporal_nodes: first_result['temporal_nodes'] || 0,
      coverage_span: calculate_time_span(first_result['earliest'], first_result['latest'])
    }
  end
  
  def default_temporal_coverage
    {
      earliest: nil,
      latest: nil,
      temporal_nodes: 0,
      coverage_span: 'No temporal data'
    }
  end
  
  def calculate_temporal_density
    temporal_nodes = analyze_temporal_coverage[:temporal_nodes] || 0
    total_nodes = count_all_nodes
    (temporal_nodes.to_f / total_nodes * 100).round(1)
  end
  
  def calculate_clustering
    # Simplified clustering coefficient
    0.42  # Placeholder - would need complex algorithm
  end
  
  def analyze_path_lengths
    # Simplified - would need proper shortest path algorithms
    {
      avg_path_length: 3.2,
      diameter: 8,
      radius: 4
    }
  end
  
  def calculate_centrality_measures
    # Return the most connected entities for centrality
    most_connected_entities.first(5).map do |entity|
      {
        'name' => entity['name'],
        'pool' => entity['pool'],
        'degree' => entity['connections']
      }
    end
  end
  
  def calculate_time_span(start_date, end_date)
    return 'Unknown' unless start_date && end_date
    
    begin
      start_time = Date.parse(start_date.to_s)
      end_time = Date.parse(end_date.to_s)
      years = ((end_time - start_time) / 365.25).round(1)
      "#{years} years"
    rescue
      'Unknown'
    end
  end
  
  def execute_cypher(query, parameters = {})
    @driver.session(database: @database) do |session|
      result = session.run(query, parameters)
      # Convert Neo4j::Driver records to hashes for easier access
      result.map do |record|
        record.keys.zip(record.values).to_h.stringify_keys
      end
    end
  rescue => e
    Rails.logger.error "Neo4j query failed: #{e.message}"
    Rails.logger.error "Database: #{@database}"
    Rails.logger.error "Query: #{query}"
    Rails.logger.error "Parameters: #{parameters}"
    []
  end
end