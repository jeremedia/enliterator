# frozen_string_literal: true

# MCP Bridge Tool for Enliterator
#
# Finds paths connecting two entities in the knowledge graph
# Returns the shortest path(s) showing how concepts are related
#
module Mcp
  class BridgeTool
    # Find paths between two entities
    # Arguments: a (string/id), b (string/id), max_paths (int), ekn (optional EKN object)
    # Returns: { paths: [ { nodes, relationships, length, description } ] }
    def self.call(a:, b:, max_paths: 3, ekn: nil)
      return { error: "Both entities (a and b) are required" } if a.blank? || b.blank?
      
      # Use provided EKN or fallback to meta-enliterator
      ekn = ekn || Ekn.find_by(slug: 'meta-enliterator') || Ekn.first
      return { error: "No EKN available" } unless ekn
      
      Rails.logger.info "MCP BridgeTool: Finding paths between '#{a}' and '#{b}'"
      
      # Parse entity IDs (could be names or IDs)
      entity_a_id = parse_entity_id(a, ekn)
      entity_b_id = parse_entity_id(b, ekn)
      
      return { error: "Could not find entity: #{a}" } unless entity_a_id
      return { error: "Could not find entity: #{b}" } unless entity_b_id
      
      # Find paths in Neo4j
      paths = find_paths(entity_a_id, entity_b_id, ekn, max_paths)
      
      # Format response
      {
        query: {
          from: a,
          to: b,
          from_id: entity_a_id,
          to_id: entity_b_id
        },
        paths: paths,
        total_paths_found: paths.size
      }
      
    rescue => e
      Rails.logger.error "MCP BridgeTool error: #{e.message}"
      Rails.logger.error e.backtrace.first(10).join("\n")
      
      { error: "Bridge search failed: #{e.message}" }
    end
    
    private
    
    # Parse entity identifier (could be ID or name)
    def self.parse_entity_id(identifier, ekn)
      # If it's numeric, treat as ID
      if identifier.to_s =~ /^\d+$/
        return identifier.to_i
      end
      
      # Otherwise, search for entity by name
      search_tool = Mcp::Tools::SimpleSearchTool.new(ekn: ekn)
      results = search_tool.execute(query: identifier, top_k: 1)
      
      if results[:items]&.any?
        results[:items].first[:entity_id]
      else
        nil
      end
    end
    
    # Find paths between two entities using Neo4j
    def self.find_paths(from_id, to_id, ekn, max_paths)
      driver = Graph::Connection.instance.driver
      session = driver.session(database: ekn.neo4j_database_name)
      
      begin
        # Use shortestPath to find connections
        # Limit relationship depth to prevent timeouts
        cypher = <<~CYPHER
          MATCH path = shortestPath((a)-[*..5]-(b))
          WHERE id(a) = $from_id AND id(b) = $to_id
          WITH path
          LIMIT #{max_paths}
          RETURN 
            [n in nodes(path) | {
              id: id(n),
              type: labels(n)[0],
              name: n.label
            }] as nodes,
            [r in relationships(path) | {
              type: type(r),
              direction: CASE 
                WHEN startNode(r) = nodes(path)[0] THEN 'outgoing' 
                ELSE 'incoming' 
              END
            }] as relationships,
            length(path) as path_length
        CYPHER
        
        result = session.run(cypher, from_id: from_id, to_id: to_id)
        
        paths = []
        result.each do |record|
          # Build path description
          description = build_path_description(record[:nodes], record[:relationships])
          
          paths << {
            nodes: record[:nodes],
            relationships: record[:relationships],
            length: record[:path_length],
            description: description
          }
        end
        
        # If no direct path found, try to find indirect connections
        if paths.empty?
          paths = find_indirect_connections(from_id, to_id, ekn, session)
        end
        
        paths
        
      ensure
        session&.close
      end
    end
    
    # Build human-readable path description
    def self.build_path_description(nodes, relationships)
      return "" if nodes.empty?
      
      parts = []
      nodes.each_with_index do |node, i|
        parts << "#{node[:type]}(#{node[:name]})"
        
        if i < relationships.length
          rel = relationships[i]
          arrow = rel[:direction] == 'outgoing' ? '→' : '←'
          parts << "#{arrow}[#{rel[:type]}]#{arrow}"
        end
      end
      
      parts.join(" ")
    end
    
    # Find indirect connections through common neighbors
    def self.find_indirect_connections(from_id, to_id, ekn, session)
      cypher = <<~CYPHER
        MATCH (a)-[r1]-(common)-[r2]-(b)
        WHERE id(a) = $from_id AND id(b) = $to_id
        WITH a, b, common, r1, r2
        LIMIT 3
        RETURN 
          {id: id(a), type: labels(a)[0], name: a.label} as node_a,
          {id: id(b), type: labels(b)[0], name: b.label} as node_b,
          {id: id(common), type: labels(common)[0], name: common.label} as common_node,
          type(r1) as rel1_type,
          type(r2) as rel2_type
      CYPHER
      
      result = session.run(cypher, from_id: from_id, to_id: to_id)
      
      paths = []
      result.each do |record|
        description = "#{record[:node_a][:type]}(#{record[:node_a][:name]}) →[#{record[:rel1_type]}]→ " +
                     "#{record[:common_node][:type]}(#{record[:common_node][:name]}) →[#{record[:rel2_type]}]→ " +
                     "#{record[:node_b][:type]}(#{record[:node_b][:name]})"
        
        paths << {
          nodes: [record[:node_a], record[:common_node], record[:node_b]],
          relationships: [
            { type: record[:rel1_type], direction: 'outgoing' },
            { type: record[:rel2_type], direction: 'outgoing' }
          ],
          length: 2,
          description: description,
          via: record[:common_node][:name]
        }
      end
      
      paths
    end
  end
end