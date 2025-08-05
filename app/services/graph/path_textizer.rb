# frozen_string_literal: true

module Graph
  # Converts graph paths to human-readable sentences using canonical names and verb glossary
  class PathTextizer
    # Verb display names for more natural language
    VERB_DISPLAY_NAMES = {
      'embodies' => 'embodies',
      'is_embodiment_of' => 'is an embodiment of',
      'elicits' => 'elicits',
      'is_elicited_by' => 'is elicited by',
      'influences' => 'influences',
      'is_influenced_by' => 'is influenced by',
      'refines' => 'refines',
      'is_refined_by' => 'is refined by',
      'version_of' => 'is a version of',
      'has_version' => 'has version',
      'co_occurs_with' => 'co-occurs with',
      'located_at' => 'is located at',
      'hosts' => 'hosts',
      'adjacent_to' => 'is adjacent to',
      'validated_by' => 'is validated by',
      'validates' => 'validates',
      'supports' => 'supports',
      'refutes' => 'refutes',
      'diffuses_through' => 'diffuses through',
      'codifies' => 'codifies',
      'derived_from' => 'is derived from',
      'inspires' => 'inspires',
      'is_inspired_by' => 'is inspired by',
      'feeds_back' => 'feeds back to',
      'is_fed_by' => 'is fed by',
      'connects_to' => 'connects to',
      'cites' => 'cites',
      'cited_by' => 'is cited by',
      'precedes' => 'precedes',
      'follows' => 'follows',
      'has_rights' => 'has rights defined by'
    }.freeze
    
    def initialize(transaction = nil)
      @tx = transaction
    end
    
    # Convert a path of node IDs and relationship types to text
    def textize_path(path_data)
      # path_data format: 
      # { nodes: [{id: 1, label: "Idea"}, ...], 
      #   edges: ["embodies", "elicits", ...] }
      
      return "" if path_data[:nodes].empty?
      
      sentences = []
      nodes = path_data[:nodes]
      edges = path_data[:edges] || []
      
      # Build the path sentence
      path_parts = []
      
      nodes.each_with_index do |node, i|
        # Add the node representation
        path_parts << format_node(node)
        
        # Add the edge if there is one
        if i < edges.length
          path_parts << " → #{format_verb(edges[i])} → "
        end
      end
      
      path_parts.join
    end
    
    # Convert a Neo4j path result to text
    def textize_cypher_path(cypher_path)
      nodes = []
      edges = []
      
      # Extract nodes and relationships from the path
      cypher_path.nodes.each do |node|
        nodes << extract_node_info(node)
      end
      
      cypher_path.relationships.each do |rel|
        edges << rel.type.downcase
      end
      
      textize_path(nodes: nodes, edges: edges)
    end
    
    # Generate a narrative sentence from a path
    def narrate_path(path_data)
      nodes = path_data[:nodes]
      edges = path_data[:edges] || []
      
      return "" if nodes.empty?
      
      if nodes.length == 1
        # Single node
        node = nodes.first
        return "#{format_node_narrative(node)}."
      elsif nodes.length == 2 && edges.length == 1
        # Simple two-node relationship
        source = nodes[0]
        target = nodes[1]
        verb = edges[0]
        
        return "#{format_node_narrative(source)} #{format_verb_narrative(verb)} #{format_node_narrative(target)}."
      else
        # Multi-hop path - break into sentences
        sentences = []
        
        nodes.each_with_index do |node, i|
          if i < edges.length
            next_node = nodes[i + 1]
            verb = edges[i]
            
            sentences << "#{format_node_narrative(node)} #{format_verb_narrative(verb)} #{format_node_narrative(next_node)}"
          end
        end
        
        # Join with appropriate connectors
        if sentences.length == 1
          sentences.first + "."
        elsif sentences.length == 2
          sentences.join(", which ") + "."
        else
          result = sentences.first
          sentences[1..-2].each do |sentence|
            result += ", which #{sentence}"
          end
          result += ", and finally #{sentences.last}."
          result
        end
      end
    end
    
    # Find and textize paths between two nodes
    def find_and_textize_paths(source_id, target_id, max_hops: 3, limit: 5)
      return [] unless @tx
      
      query = <<~CYPHER
        MATCH path = shortestPath((source)-[*1..#{max_hops}]-(target))
        WHERE source.id = $source_id AND target.id = $target_id
        RETURN path
        LIMIT #{limit}
      CYPHER
      
      paths = []
      
      @tx.run(query, source_id: source_id, target_id: target_id).each do |record|
        path = record[:path]
        paths << {
          text: textize_cypher_path(path),
          narrative: narrate_path(extract_path_data(path)),
          length: path.relationships.length
        }
      end
      
      paths
    end
    
    private
    
    def format_node(node_info)
      label = node_info[:label] || node_info['label']
      name = node_info[:name] || node_info['name'] || 
             node_info[:canonical_name] || node_info['canonical_name'] ||
             node_info[:repr_text] || node_info['repr_text'] ||
             "#{label} ##{node_info[:id] || node_info['id']}"
      
      "#{label}(#{name})"
    end
    
    def format_node_narrative(node_info)
      label = node_info[:label] || node_info['label']
      name = node_info[:name] || node_info['name'] || 
             node_info[:canonical_name] || node_info['canonical_name'] ||
             node_info[:repr_text] || node_info['repr_text']
      
      case label.downcase
      when 'idea'
        "the idea of '#{name}'"
      when 'manifest'
        "the manifestation '#{name}'"
      when 'experience'
        name ? "the experience '#{name}'" : "an experience"
      when 'practical'
        "the practice '#{name}'"
      when 'emanation'
        "the influence '#{name}'"
      when 'evolutionary'
        "the evolution '#{name}'"
      when 'relational'
        "the relationship '#{name}'"
      when 'spatial'
        "the location '#{name}'"
      else
        "'#{name}'"
      end
    end
    
    def format_verb(verb)
      verb_lower = verb.downcase
      VERB_DISPLAY_NAMES[verb_lower] || verb_lower
    end
    
    def format_verb_narrative(verb)
      format_verb(verb)
    end
    
    def extract_node_info(neo4j_node)
      {
        id: neo4j_node['id'],
        label: neo4j_node.labels.first,
        name: neo4j_node['label'] || neo4j_node['canonical_name'] || 
              neo4j_node['repr_text'] || neo4j_node['term']
      }
    end
    
    def extract_path_data(cypher_path)
      nodes = cypher_path.nodes.map { |node| extract_node_info(node) }
      edges = cypher_path.relationships.map { |rel| rel.type.downcase }
      
      { nodes: nodes, edges: edges }
    end
  end
end