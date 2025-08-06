# Service to query the Neo4j knowledge graph
# This connects the Navigator to actual data from the pipeline
#
# Database-per-EKN Architecture (2025-08-06)
# ==========================================
# Each EKN has its own Neo4j database for complete data isolation:
# - Medical research data never mixes with festival data
# - Clean backup/restore per EKN
# - Database-level security
# 
# The default 'neo4j' database contains 280k nodes from initial import
# New EKNs get their own databases: ekn_1, ekn_2, etc.
#
# To verify Neo4j has data: rails runner script/check_neo4j_health.rb
#
module Graph
  class QueryService
    def initialize(ekn_or_database_name = nil)
      if ekn_or_database_name.is_a?(IngestBatch)
        @ekn = ekn_or_database_name
        @database_name = @ekn.neo4j_database_name
        @ekn.ensure_neo4j_database_exists!
      elsif ekn_or_database_name.is_a?(String)
        @database_name = ekn_or_database_name
      else
        # Default to main database for backward compatibility
        # This contains the 280k nodes from initial import
        @database_name = 'neo4j'
      end
      
      @driver = Graph::Connection.instance.driver
      Rails.logger.debug "Graph::QueryService using database: #{@database_name}"
    end
    
    def search_entities(query_text, limit: 10)
      session = @driver.session(database: @database_name)
      
      cypher = <<~CYPHER
        MATCH (n)
        WHERE n.name =~ $pattern OR n.label =~ $pattern
        RETURN n
        ORDER BY n.name
        LIMIT $limit
      CYPHER
      
      result = session.run(
        cypher,
        pattern: "(?i).*#{query_text}.*",
        limit: limit
      )
      
      entities = result.map do |record|
        node = record['n']
        {
          id: node['id'],
          name: node['name'] || node['label'],
          type: node.labels.first,
          properties: node.properties
        }
      end
      
      entities
    ensure
      session&.close
    end
    
    def search_entities(query, limit: 10)
      session = @driver.session(database: @database_name)
      
      # If query is empty, return sample entities
      if query.nil? || query.empty?
        cypher = <<~CYPHER
          MATCH (n)
          RETURN n
          LIMIT #{limit}
        CYPHER
        
        result = session.run(cypher)
      else
        # Search by name or label containing the query
        cypher = <<~CYPHER
          MATCH (n)
          WHERE toLower(n.name) CONTAINS toLower($query) 
             OR toLower(n.label) CONTAINS toLower($query)
             OR toLower(n.canonical) CONTAINS toLower($query)
          RETURN n
          LIMIT #{limit}
        CYPHER
        
        result = session.run(
          cypher,
          query: query
        )
      end
      
      entities = []
      result.each do |record|
        node = record['n']
        props = node.properties.to_h.symbolize_keys
        entities << {
          id: props[:id],
          name: props[:label] || props[:name] || props[:canonical] || 'Unnamed',
          type: node.labels.first,
          description: props[:description],
          properties: props
        }
      end
      
      entities
    ensure
      session&.close
    end
    
    def get_entity_details(entity_id)
      session = @driver.session(database: @database_name)
      
      cypher = <<~CYPHER
        MATCH (n {id: $id})
        OPTIONAL MATCH (n)-[r]-(connected)
        RETURN n, collect(DISTINCT {
          relationship: type(r),
          direction: CASE WHEN startNode(r) = n THEN 'outgoing' ELSE 'incoming' END,
          connected: connected
        }) as connections
      CYPHER
      
      result = session.run(
        cypher,
        id: entity_id
      )
      
      record = result.single
      return nil unless record
      
      node = record['n']
      connections = record['connections']
      
      {
        id: node['id'],
        name: node['name'] || node['label'],
        type: node.labels.first,
        properties: node.properties,
        connections: connections.map do |conn|
          next unless conn['connected']
          {
            relationship: conn['relationship'],
            direction: conn['direction'],
            entity: {
              id: conn['connected']['id'],
              name: conn['connected']['name'] || conn['connected']['label'],
              type: conn['connected'].labels.first
            }
          }
        end.compact
      }
    ensure
      session&.close
    end
    
    def find_paths(from_id, to_id, max_length: 3)
      session = @driver.session(database: @database_name)
      
      cypher = <<~CYPHER
        MATCH path = shortestPath((a {id: $from_id})-[*..#{max_length}]-(b {id: $to_id}))
        RETURN path
      CYPHER
      
      result = session.run(
        cypher,
        from_id: from_id,
        to_id: to_id
      )
      
      paths = result.map do |record|
        path = record['path']
        nodes = path.nodes.map do |n|
          props = n.properties.to_h.symbolize_keys
          { 
            id: props[:id], 
            name: props[:label] || props[:name] || props[:canonical] || props[:title] || "Entity#{props[:id]}",
            type: n.labels.first
          }
        end
        relationships = path.relationships.map { |r| r.type }
        
        # Generate path text description
        path_text = generate_path_text(nodes, relationships)
        
        {
          nodes: nodes,
          relationships: relationships,
          path_text: path_text
        }
      end
      
      paths
    ensure
      session&.close
    end
    
    def get_statistics
      session = @driver.session(database: @database_name)
      
      cypher = <<~CYPHER
        MATCH (n)
        WITH labels(n) as node_labels
        UNWIND node_labels as label
        RETURN label, count(*) as count
        ORDER BY count DESC
      CYPHER
      
      result = session.run(cypher)
      
      stats = {
        nodes_by_type: {},
        total_nodes: 0
      }
      
      result.each do |record|
        label = record['label']
        count = record['count']
        stats[:nodes_by_type][label] = count
        stats[:total_nodes] += count
      end
      
      # Get relationship count
      cypher = <<~CYPHER
        MATCH (n)
        MATCH (n)-[r]-()
        RETURN count(DISTINCT r) as rel_count
      CYPHER
      
      result = session.run(cypher)
      stats[:total_relationships] = result.single&.[]('rel_count') || 0
      
      stats
    ensure
      session&.close
    end
    
    def close
      @driver&.close
    end
    
    private
    
    def generate_path_text(nodes, relationships)
      return "No path found" if nodes.empty?
      
      # Include node type for clarity
      node_descriptions = nodes.map { |n| "#{n[:name]} (#{n[:type]})" }
      return node_descriptions.first if nodes.size == 1
      
      text_parts = []
      node_descriptions.each_with_index do |desc, i|
        text_parts << desc
        if i < relationships.size
          text_parts << " →#{relationships[i]}→ "
        end
      end
      
      text_parts.join('')
    end
    
    def batch_filter(alias_name = 'n')
      # No longer needed with database-per-EKN architecture
      # Each EKN has its own database, so no filtering required
      ""
    end
  end
end