# Fetches and formats graph data specifically for visualizations
# Provides optimized queries for different visualization types
module Graph
  class VisualizationDataService
    def initialize(database_name)
      @database_name = database_name
      @connection = Graph::Connection.instance
    end
    
    # Get pipeline stage connections for flow diagram
    def pipeline_stages_flow
      query = <<~CYPHER
        MATCH (s:Service)
        WHERE s.stage IS NOT NULL
        WITH s
        ORDER BY s.stage
        OPTIONAL MATCH (s)-[r:CALLS|TRIGGERS|DEPENDS_ON]->(s2:Service)
        WHERE s2.stage IS NOT NULL
        RETURN 
          s.stage as stage,
          s.name as name, 
          s.description as description,
          collect({
            target_stage: s2.stage,
            target_name: s2.name,
            relationship: type(r)
          }) as connections
        ORDER BY s.stage
      CYPHER
      
      execute_query(query)
    end
    
    # Get extraction service dependencies
    def extraction_services_network
      query = <<~CYPHER
        MATCH (s:Service)
        WHERE s.name CONTAINS 'Extract' OR s.name CONTAINS 'extraction'
        OPTIONAL MATCH (s)-[r:USES|DEPENDS_ON|CALLS]->(s2:Service)
        RETURN 
          s.name as service,
          s.description as description,
          labels(s) as labels,
          collect({
            target: s2.name,
            relationship: type(r),
            target_labels: labels(s2)
          }) as dependencies
      CYPHER
      
      execute_query(query)
    end
    
    # Get Ten Pool Canon structure
    def ten_pool_canon
      query = <<~CYPHER
        MATCH (p:Pool)
        OPTIONAL MATCH (p)-[r:FLOWS_TO|FEEDS|INFLUENCES]->(p2:Pool)
        RETURN 
          p.name as pool,
          p.description as description,
          p.canonical as canonical_name,
          collect({
            target: p2.name,
            relationship: type(r),
            strength: r.strength
          }) as relationships
      CYPHER
      
      result = execute_query(query)
      
      # If no Pool nodes exist, return conceptual structure
      if result.empty?
        conceptual_ten_pools
      else
        result
      end
    end
    
    # Get MCP tools and their graph connections
    def mcp_graph_connections
      query = <<~CYPHER
        MATCH (m:MCPTool)
        OPTIONAL MATCH (m)-[r]->(target)
        WHERE target:Service OR target:Model OR target:Graph
        RETURN 
          m.name as tool,
          m.description as description,
          collect({
            target_name: target.name,
            target_type: labels(target)[0],
            relationship: type(r)
          }) as connections
      CYPHER
      
      result = execute_query(query)
      
      # If no MCP nodes, get service connections
      if result.empty?
        service_based_mcp_connections
      else
        result
      end
    end
    
    # Get arbitrary subgraph for entities
    def entity_subgraph(entity_names, depth: 2)
      query = <<~CYPHER
        MATCH (n)
        WHERE n.name IN $names OR n.canonical IN $names
        OPTIONAL MATCH path = (n)-[r*1..#{depth}]-(connected)
        WITH n, collect(DISTINCT connected) as connected_nodes, 
             collect(relationships(path)) as all_paths
        UNWIND connected_nodes as cn
        OPTIONAL MATCH (n)-[rel]-(cn)
        RETURN 
          collect(DISTINCT n) + collect(DISTINCT cn) as nodes,
          collect(DISTINCT rel) as relationships
      CYPHER
      
      execute_query(query, names: entity_names)
    end
    
    # Convert raw Neo4j data to D3-compatible format
    def format_for_d3(nodes, relationships)
      formatted_nodes = nodes.map do |node|
        {
          id: node[:id] || node[:name],
          name: node[:name] || node[:canonical],
          label: node[:name] || node[:canonical],
          type: node[:labels]&.first || 'Entity',
          pool: determine_pool(node),
          properties: node.except(:id, :name, :canonical, :labels)
        }
      end
      
      formatted_relationships = relationships.map do |rel|
        {
          source: rel[:start] || rel[:from],
          target: rel[:end] || rel[:to],
          type: rel[:type] || rel[:relationship],
          weight: rel[:weight] || rel[:strength] || 1,
          properties: rel.except(:start, :end, :from, :to, :type, :relationship)
        }
      end
      
      {
        nodes: formatted_nodes,
        links: formatted_relationships
      }
    end
    
    private
    
    def execute_query(cypher, params = {})
      session = @connection.driver.session(database: @database_name)
      result = session.run(cypher, params)
      result.map(&:to_h)
    rescue => e
      Rails.logger.error "VisualizationDataService query error: #{e.message}"
      []
    ensure
      session&.close
    end
    
    def determine_pool(node)
      # Determine which pool a node belongs to based on labels or properties
      labels = node[:labels] || []
      
      pool_mapping = {
        'Idea' => 'idea',
        'Manifest' => 'manifest',
        'Experience' => 'experience',
        'Relational' => 'relational',
        'Evolutionary' => 'evolutionary',
        'Practical' => 'practical',
        'Emanation' => 'emanation',
        'Intent' => 'intent',
        'Spatial' => 'spatial',
        'Actor' => 'actor'
      }
      
      labels.each do |label|
        return pool_mapping[label] if pool_mapping[label]
      end
      
      'unknown'
    end
    
    def conceptual_ten_pools
      # Return conceptual structure when no Pool nodes exist
      [
        {
          pool: "Idea",
          description: "Abstract concepts and principles",
          canonical_name: "idea",
          relationships: [
            { target: "Manifest", relationship: "EMBODIES", strength: 1.0 },
            { target: "Intent", relationship: "GUIDES", strength: 0.8 }
          ]
        },
        {
          pool: "Manifest",
          description: "Physical representations and artifacts",
          canonical_name: "manifest",
          relationships: [
            { target: "Experience", relationship: "CREATES", strength: 0.9 },
            { target: "Practical", relationship: "REQUIRES", strength: 0.7 }
          ]
        },
        {
          pool: "Experience",
          description: "Subjective encounters and stories",
          canonical_name: "experience",
          relationships: [
            { target: "Relational", relationship: "INVOLVES", strength: 0.8 },
            { target: "Evolutionary", relationship: "TRANSFORMS", strength: 0.6 }
          ]
        },
        {
          pool: "Relational",
          description: "Connections between entities",
          canonical_name: "relational",
          relationships: [
            { target: "Actor", relationship: "CONNECTS", strength: 0.9 }
          ]
        },
        {
          pool: "Evolutionary",
          description: "Changes and progressions over time",
          canonical_name: "evolutionary",
          relationships: [
            { target: "Experience", relationship: "GENERATES", strength: 0.7 }
          ]
        },
        {
          pool: "Practical",
          description: "Methods and implementations",
          canonical_name: "practical",
          relationships: [
            { target: "Manifest", relationship: "ENABLES", strength: 0.8 }
          ]
        },
        {
          pool: "Emanation",
          description: "Consequences and ripple effects",
          canonical_name: "emanation",
          relationships: [
            { target: "Experience", relationship: "CAUSES", strength: 0.5 }
          ]
        }
      ]
    end
    
    def service_based_mcp_connections
      # Fallback when no MCPTool nodes exist
      query = <<~CYPHER
        MATCH (s:Service)
        WHERE s.name CONTAINS 'MCP' OR s.name CONTAINS 'mcp'
        OPTIONAL MATCH (s)-[r]-(connected)
        WHERE connected:Service OR connected:Model
        RETURN 
          s.name as tool,
          s.description as description,
          collect({
            target_name: connected.name,
            target_type: labels(connected)[0],
            relationship: type(r)
          }) as connections
        LIMIT 10
      CYPHER
      
      execute_query(query)
    end
  end
end