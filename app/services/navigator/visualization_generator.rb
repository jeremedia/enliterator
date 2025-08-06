# Generates visualizations from Neo4j data based on intent
# This transforms knowledge into visual landscapes

module Navigator
  class VisualizationGenerator
    def initialize(ekn:)
      @ekn = ekn
      # IMPORTANT: Passing nil instead of ekn.id because Neo4j nodes don't have batch_id
      # The graph contains 280k+ nodes but they're not filtered by batch
      # See docs/NEO4J_SETUP.md for details
      @graph_service = Graph::QueryService.new(nil)  # Query ALL data, not filtered by batch
      @intent_recognizer = VisualizationIntentRecognizer.new
    end
    
    def generate_for_query(user_input, conversation_context = {})
      # Recognize visualization intent
      intent = @intent_recognizer.recognize(user_input)
      
      return nil unless intent || @intent_recognizer.should_visualize?(user_input, conversation_context)
      
      # Default to relationship graph if we should visualize but no specific type
      viz_type = intent&.dig(:type) || 'relationship_graph'
      
      case viz_type
      when 'relationship_graph'
        generate_relationship_graph(user_input, conversation_context)
      when 'timeline'
        generate_timeline(user_input, conversation_context)
      when 'comparison_chart'
        generate_comparison(user_input, conversation_context)
      else
        Rails.logger.info "Visualization type #{viz_type} not yet implemented"
        nil
      end
    end
    
    private
    
    def generate_relationship_graph(query, context)
      # Extract entities from the query or context
      entities = extract_relevant_entities(query, context)
      
      # Get subgraph from Neo4j
      graph_data = if entities.any?
        fetch_entity_subgraph(entities)
      else
        fetch_sample_graph
      end
      
      return nil if graph_data[:nodes].empty?
      
      # Format for D3.js visualization
      {
        type: 'relationship_graph',
        data: {
          nodes: format_nodes_for_d3(graph_data[:nodes]),
          relationships: format_relationships_for_d3(graph_data[:relationships])
        },
        query: query,
        description: describe_graph(graph_data),
        instructions: "Click nodes to explore • Drag to rearrange • Scroll to zoom"
      }
    end
    
    def extract_relevant_entities(query, context)
      # Search for entities mentioned in the query
      words = query.downcase.split(/\W+/) - %w[what how does show me the connect relationship between]
      
      entities = []
      words.each do |word|
        next if word.length < 3
        
        results = @graph_service.search_entities(word, limit: 5)
        entities.concat(results) if results.any?
      end
      
      # Also include entities from conversation context if available
      if context[:entities].present?
        entities.concat(context[:entities])
      end
      
      entities.uniq { |e| e[:id] }
    end
    
    def fetch_entity_subgraph(entities, depth: 2)
      return { nodes: [], relationships: [] } if entities.empty?
      
      session = @graph_service.instance_variable_get(:@driver).session
      
      # Get subgraph around the entities
      entity_ids = entities.map { |e| e[:id] }
      
      cypher = <<~CYPHER
        MATCH (n)
        WHERE n.id IN $entity_ids
        OPTIONAL MATCH path = (n)-[r*1..#{depth}]-(connected)
        WITH n, connected, relationships(path) as rels
        RETURN 
          collect(DISTINCT n) + collect(DISTINCT connected) as nodes,
          reduce(allRels = [], r in collect(rels) | allRels + r) as relationships
      CYPHER
      
      result = session.run(cypher, entity_ids: entity_ids)
      record = result.single
      
      return { nodes: [], relationships: [] } unless record
      
      nodes = record['nodes'].compact.uniq.map do |node|
        props = node.properties.to_h.symbolize_keys
        {
          id: props[:id],
          name: props[:label] || props[:name] || props[:canonical] || "Entity #{props[:id]}",
          type: node.labels.first,
          properties: props,
          connection_count: 0 # Will be calculated below
        }
      end
      
      relationships = record['relationships'].compact.uniq.map do |rel|
        {
          start: rel.start_element_id.split(':').last.to_i,
          end: rel.end_element_id.split(':').last.to_i,
          type: rel.type,
          properties: rel.properties.to_h.symbolize_keys
        }
      end
      
      # Calculate connection counts
      nodes.each do |node|
        node[:connection_count] = relationships.count { |r| 
          r[:start] == node[:id] || r[:end] == node[:id] 
        }
      end
      
      { nodes: nodes, relationships: relationships }
    rescue => e
      Rails.logger.error "Error fetching subgraph: #{e.message}"
      { nodes: [], relationships: [] }
    ensure
      session&.close
    end
    
    def fetch_sample_graph(limit: 20)
      session = @graph_service.instance_variable_get(:@driver).session
      
      # Get a sample of well-connected nodes
      cypher = <<~CYPHER
        MATCH (n)
        WITH n, COUNT {(n)-[]-()}  as degree
        ORDER BY degree DESC
        LIMIT #{limit}
        OPTIONAL MATCH (n)-[r]-(connected)
        WHERE connected IN [n]
        RETURN 
          collect(DISTINCT n) as nodes,
          collect(DISTINCT r) as relationships
      CYPHER
      
      result = session.run(cypher)
      record = result.single
      
      return { nodes: [], relationships: [] } unless record
      
      nodes = record['nodes'].map do |node|
        props = node.properties.to_h.symbolize_keys
        {
          id: props[:id],
          name: props[:label] || props[:name] || props[:canonical] || "Entity #{props[:id]}",
          type: node.labels.first,
          properties: props,
          connection_count: 0
        }
      end
      
      relationships = record['relationships'].compact.map do |rel|
        {
          start: rel.start_element_id.split(':').last.to_i,
          end: rel.end_element_id.split(':').last.to_i,
          type: rel.type,
          properties: rel.properties.to_h.symbolize_keys
        }
      end
      
      # Calculate connection counts
      nodes.each do |node|
        node[:connection_count] = relationships.count { |r| 
          r[:start] == node[:id] || r[:end] == node[:id] 
        }
      end
      
      { nodes: nodes, relationships: relationships }
    rescue => e
      Rails.logger.error "Error fetching sample graph: #{e.message}"
      { nodes: [], relationships: [] }
    ensure
      session&.close
    end
    
    def format_nodes_for_d3(nodes)
      nodes.map do |node|
        {
          id: node[:id],
          name: node[:name],
          label: node[:name], # For display
          type: node[:type],
          pool: node[:type], # Pool type for coloring
          properties: node[:properties],
          connection_count: node[:connection_count]
        }
      end
    end
    
    def format_relationships_for_d3(relationships)
      relationships.map do |rel|
        {
          source: rel[:start],
          target: rel[:end],
          start: rel[:start], # Alternative naming
          end: rel[:end],     # Alternative naming
          type: rel[:type],
          relationship: rel[:type], # Alternative naming
          properties: rel[:properties],
          weight: rel[:properties][:weight] || 1
        }
      end
    end
    
    def describe_graph(graph_data)
      node_count = graph_data[:nodes].size
      rel_count = graph_data[:relationships].size
      
      # Count nodes by type
      type_counts = graph_data[:nodes].group_by { |n| n[:type] }
                                       .transform_values(&:count)
                                       .sort_by { |_, count| -count }
      
      # Find most connected nodes
      most_connected = graph_data[:nodes].sort_by { |n| -n[:connection_count] }
                                          .first(3)
                                          .map { |n| n[:name] }
      
      description = "Showing #{node_count} entities with #{rel_count} relationships. "
      
      if type_counts.any?
        description += "Includes #{type_counts.map { |type, count| "#{count} #{type}" }.join(', ')}. "
      end
      
      if most_connected.any?
        description += "Key nodes: #{most_connected.join(', ')}."
      end
      
      description
    end
    
    def generate_timeline(query, context)
      # TODO: Implement timeline visualization
      Rails.logger.info "Timeline visualization requested but not yet implemented"
      nil
    end
    
    def generate_comparison(query, context)
      # TODO: Implement comparison visualization
      Rails.logger.info "Comparison visualization requested but not yet implemented"
      nil
    end
  end
end