# frozen_string_literal: true

module Graph
  # Centralized service for locating nodes in Neo4j and resolving their labels
  # Provides a single source of truth for node identification across different pool types
  class NodeLocator
    attr_reader :driver, :database

    def initialize(ekn:)
      @ekn = ekn
      @database = ekn.neo4j_database_name
      @driver = Connection.instance.driver
    end

    # Find a node by pool type and identifier
    # Returns node properties or nil if not found
    def find_node(pool_type:, identifier:)
      pool_type = normalize_pool_type(pool_type)
      property_name = identifier_property_for(pool_type)
      
      @driver.session(database: @database) do |session|
        session.read_transaction do |tx|
          query = <<~CYPHER
            MATCH (n:#{pool_type})
            WHERE n.#{property_name} = $identifier
            RETURN n
            LIMIT 1
          CYPHER
          
          result = tx.run(query, identifier: identifier)
          record = result.single
          return nil unless record
          
          extract_node_data(record['n'])
        end
      end
    rescue Neo4j::Driver::Exceptions::NoSuchRecordException => e
      Rails.logger.debug "NodeLocator: Node not found - #{e.message}"
      nil
    rescue => e
      Rails.logger.error "NodeLocator: Failed to find node - #{e.message}"
      nil
    end

    # Find multiple nodes by their identifiers
    def find_nodes(nodes_spec)
      found_nodes = {}
      
      @driver.session(database: @database) do |session|
        session.read_transaction do |tx|
          nodes_spec.each do |spec|
            pool_type = normalize_pool_type(spec[:pool_type] || spec[:pool])
            identifier = spec[:identifier] || spec[:label] || spec[:id]
            property_name = identifier_property_for(pool_type)
            
            query = <<~CYPHER
              MATCH (n:#{pool_type})
              WHERE n.#{property_name} = $identifier
              RETURN n
              LIMIT 1
            CYPHER
            
            result = tx.run(query, identifier: identifier)
            record = result.single
            
            if record
              found_nodes[spec] = extract_node_data(record['n'])
            else
              Rails.logger.warn "NodeLocator: Node not found - #{pool_type}:#{identifier}"
            end
          end
        end
      end
      
      found_nodes
    end

    # Get the canonical label for a node
    def canonical_label_for(node_or_properties)
      return nil unless node_or_properties
      
      # Handle both node objects and property hashes
      properties = if node_or_properties.respond_to?(:properties)
                    node_or_properties.properties
                  else
                    node_or_properties
                  end
      
      # Determine pool type from labels or properties
      pool_type = properties[:pool_type] || properties['pool_type']
      
      # If no explicit pool_type, try to infer from labels
      if pool_type.nil? && properties[:labels]
        pool_type = properties[:labels].first
      elsif pool_type.nil? && properties['labels']
        pool_type = properties['labels'].first
      end
      
      pool_type = normalize_pool_type(pool_type) if pool_type
      
      # Get the appropriate field based on pool type
      case pool_type
      when 'Idea', 'Manifest', 'Person', 'Troupe', 'Genre', 'Emanation'
        properties['label'] || properties[:label]
      when 'Practical', 'Method'
        properties['goal'] || properties[:goal] || properties['label'] || properties[:label]
      when 'Experience', 'Event'
        properties['narrative_text'] || properties[:narrative_text] || 
        properties['agent_label'] || properties[:agent_label] ||
        properties['label'] || properties[:label]
      when 'Lexicon'
        properties['term'] || properties[:term] || properties['label'] || properties[:label]
      else
        # Fallback: try common fields
        properties['label'] || properties[:label] || 
        properties['goal'] || properties[:goal] ||
        properties['narrative_text'] || properties[:narrative_text] ||
        properties['name'] || properties[:name]
      end
    end

    # Get the identifier property name for a pool type
    def identifier_property_for(pool_type)
      pool_type = normalize_pool_type(pool_type)
      
      case pool_type
      when 'Idea', 'Manifest', 'Person', 'Troupe', 'Genre', 'Emanation'
        'label'
      when 'Practical', 'Method'
        'goal'
      when 'Experience', 'Event'
        'narrative_text'
      when 'Lexicon'
        'term'
      else
        'label'  # Default fallback
      end
    end

    # Verify nodes exist before attempting to create relationships
    def verify_nodes_exist(source_spec, target_spec)
      source_node = find_node(
        pool_type: source_spec[:pool_type] || source_spec[:pool],
        identifier: source_spec[:label] || source_spec[:identifier]
      )
      
      target_node = find_node(
        pool_type: target_spec[:pool_type] || target_spec[:pool],
        identifier: target_spec[:label] || target_spec[:identifier]
      )
      
      {
        source: source_node,
        target: target_node,
        both_exist: source_node.present? && target_node.present?
      }
    end

    private

    def normalize_pool_type(pool_type)
      return nil unless pool_type
      
      # Handle string or symbol input
      pool_str = pool_type.to_s
      
      # Capitalize first letter for Neo4j labels
      pool_str = pool_str.capitalize unless pool_str == pool_str.upcase
      
      # Handle special cases
      case pool_str.downcase
      when 'ideas' then 'Idea'
      when 'practicals' then 'Practical'
      when 'experiences' then 'Experience'
      when 'manifests' then 'Manifest'
      when 'persons' then 'Person'
      when 'troupes' then 'Troupe'
      when 'genres' then 'Genre'
      when 'emanations' then 'Emanation'
      when 'events' then 'Event'
      when 'methods' then 'Method'
      when 'lexicons' then 'Lexicon'
      else pool_str
      end
    end

    def extract_node_data(node)
      return nil unless node
      
      {
        id: node.id,
        labels: node.labels,
        pool_type: node.labels.first,
        properties: node.properties,
        canonical_label: canonical_label_for(node.properties)
      }
    end
  end
end