# frozen_string_literal: true

module Graph
  # Removes orphaned nodes from the graph (nodes with no relationships)
  class OrphanRemover
    # Node types that should always have relationships
    MUST_HAVE_RELATIONSHIPS = %w[
      Idea Manifest Experience Relational Evolutionary 
      Practical Emanation
    ].freeze
    
    # Node types that can exist without relationships
    CAN_BE_ISOLATED = %w[
      ProvenanceAndRights Lexicon Intent Actor Spatial 
      Evidence Risk Method
    ].freeze
    
    def initialize(transaction)
      @tx = transaction
      @removed_count = 0
      @removal_details = []
    end
    
    def remove_all
      Rails.logger.info "Starting orphan removal"
      
      MUST_HAVE_RELATIONSHIPS.each do |label|
        remove_orphans_for_label(label)
      end
      
      # Also check for completely disconnected nodes of any type
      remove_completely_disconnected_nodes
      
      {
        removed_count: @removed_count,
        details: @removal_details
      }
    end
    
    private
    
    def remove_orphans_for_label(label)
      # Find nodes with no relationships (except rights relationship)
      query = <<~CYPHER
        MATCH (n:#{label})
        WHERE NOT (n)-[:HAS_RIGHTS]-() 
          AND size([(n)-[r]-() WHERE type(r) <> 'HAS_RIGHTS' | r]) = 0
        RETURN n.id as id, n.label as node_label, n.repr_text as repr_text
        LIMIT 100
      CYPHER
      
      loop do
        result = @tx.run(query)
        orphans = result.to_a
        
        break if orphans.empty?
        
        orphans.each do |record|
          remove_orphan_node(label, record[:id], record[:node_label] || record[:repr_text])
        end
      end
    end
    
    def remove_completely_disconnected_nodes
      # Find any nodes with absolutely no relationships
      query = <<~CYPHER
        MATCH (n)
        WHERE size([(n)-[r]-() | r]) = 0
        RETURN n.id as id, labels(n)[0] as label, 
               n.label as node_label, n.repr_text as repr_text
        LIMIT 100
      CYPHER
      
      loop do
        result = @tx.run(query)
        orphans = result.to_a
        
        break if orphans.empty?
        
        orphans.each do |record|
          label = record[:label]
          
          # Skip node types that can be isolated
          next if CAN_BE_ISOLATED.include?(label)
          
          remove_orphan_node(label, record[:id], 
                           record[:node_label] || record[:repr_text] || "Unknown")
        end
      end
    end
    
    def remove_orphan_node(label, node_id, description)
      Rails.logger.info "Removing orphaned #{label} node: #{node_id} (#{description})"
      
      # Before removing, check if this is a legitimate isolated node
      if should_preserve_node?(label, node_id)
        Rails.logger.info "Preserving #{label} node #{node_id} - legitimate isolated node"
        return
      end
      
      # Delete the orphan node
      delete_query = <<~CYPHER
        MATCH (n:#{label} {id: $node_id})
        DELETE n
        RETURN count(n) as deleted
      CYPHER
      
      result = @tx.run(delete_query, node_id: node_id).single
      
      if result[:deleted] > 0
        @removed_count += 1
        @removal_details << {
          label: label,
          id: node_id,
          description: description,
          reason: "No relationships found"
        }
      end
    end
    
    def should_preserve_node?(label, node_id)
      # Check if node should be preserved despite being orphaned
      
      case label
      when 'ProvenanceAndRights'
        # Rights nodes should always be preserved
        true
      when 'Lexicon'
        # Lexicon entries might not have relationships initially
        true
      when 'Intent'
        # Intent nodes might exist before being connected
        check_recent_node(label, node_id)
      else
        # Check if this is a very recently created node (within last hour)
        # to avoid removing nodes that are still being processed
        check_recent_node(label, node_id)
      end
    end
    
    def check_recent_node(label, node_id)
      # Check if node was created very recently
      query = <<~CYPHER
        MATCH (n:#{label} {id: $node_id})
        WHERE n.created_at > timestamp() - 3600000  // Within last hour
        RETURN count(n) > 0 as is_recent
      CYPHER
      
      result = @tx.run(query, node_id: node_id).single
      result[:is_recent]
    rescue
      # If created_at doesn't exist, preserve the node to be safe
      true
    end
  end
end