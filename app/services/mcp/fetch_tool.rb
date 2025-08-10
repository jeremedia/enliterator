# frozen_string_literal: true

# MCP Fetch Tool for Enliterator
#
# Required by ChatGPT/Deep Research integration
# Returns full entity details with id, title, text, url, and metadata
#
# This tool retrieves complete information about a specific entity
# from the Neo4j knowledge graph, including relationships and context
#
module Mcp
  class FetchTool
    # ChatGPT requires exactly this response format
    # Arguments: id (string)
    # Returns: { id, title, text, url, metadata }
    def self.call(id:)
      return { error: "ID is required" } if id.blank?
      
      # Parse entity ID (could be just a number or "entity_123" format)
      entity_id = id.to_s.gsub(/^entity_/, '').to_i
      
      # Get the default EKN
      ekn = Ekn.find_by(slug: 'meta-enliterator') || Ekn.first
      return { error: "No EKN available" } unless ekn
      
      Rails.logger.info "MCP FetchTool: fetching entity #{entity_id} from EKN #{ekn.slug}"
      
      # Fetch from Neo4j
      driver = Graph::Connection.instance.driver
      session = driver.session(database: ekn.neo4j_database_name)
      
      begin
        # Get the entity and its relationships
        cypher = <<~CYPHER
          MATCH (n)
          WHERE id(n) = $entity_id
          OPTIONAL MATCH (n)-[r]-(related)
          WITH n, collect(DISTINCT {
            type: type(r),
            direction: CASE WHEN startNode(r) = n THEN 'outgoing' ELSE 'incoming' END,
            related_id: id(related),
            related_label: related.label,
            related_type: labels(related)[0]
          }) as relationships
          RETURN 
            id(n) as entity_id,
            labels(n)[0] as entity_type,
            n.label as entity_name,
            n.repr_text as content,
            n as properties,
            relationships
        CYPHER
        
        result = session.run(cypher, entity_id: entity_id)
        record = result.single
        
        unless record
          return { error: "Entity not found: #{id}" }
        end
        
        # Build full text content
        full_text = build_full_text(record)
        
        # Build entity URL
        entity_url = build_entity_url(ekn, entity_id)
        
        # Build metadata
        metadata = build_metadata(record)
        
        # Return in exact format required by ChatGPT
        {
          id: id,
          title: record[:entity_name] || "Entity #{entity_id}",
          text: full_text,
          url: entity_url,
          metadata: metadata
        }
        
      rescue => e
        Rails.logger.error "MCP FetchTool error: #{e.message}"
        Rails.logger.error e.backtrace.first(10).join("\n")
        
        { error: "Fetch failed: #{e.message}" }
      ensure
        session&.close
      end
    end
    
    private
    
    # Build comprehensive text content
    def self.build_full_text(record)
      parts = []
      
      # Entity header
      entity_type = record[:entity_type]
      entity_name = record[:entity_name]
      parts << "# #{entity_type}: #{entity_name}"
      parts << ""
      
      # Main content
      if record[:content].present?
        parts << "## Description"
        parts << record[:content]
        parts << ""
      end
      
      # Properties
      if record[:properties]
        relevant_props = extract_relevant_properties(record[:properties])
        if relevant_props.any?
          parts << "## Properties"
          relevant_props.each do |key, value|
            parts << "- #{key}: #{value}"
          end
          parts << ""
        end
      end
      
      # Relationships
      if record[:relationships]&.any?
        parts << "## Relationships"
        
        # Group by relationship type
        grouped = record[:relationships].group_by { |r| r[:type] }
        
        grouped.each do |rel_type, rels|
          parts << "\n### #{rel_type.humanize}"
          rels.each do |rel|
            direction = rel[:direction] == 'outgoing' ? '→' : '←'
            parts << "- #{direction} #{rel[:related_type]}(#{rel[:related_label]})"
          end
        end
        parts << ""
      end
      
      # Join all parts
      parts.join("\n")
    end
    
    # Build entity URL
    def self.build_entity_url(ekn, entity_id)
      base_url = ENV['APP_BASE_URL'] || 'https://e.dev.domt.app'
      "#{base_url}/ekns/#{ekn.slug}/entities/#{entity_id}"
    end
    
    # Build metadata object
    def self.build_metadata(record)
      metadata = {
        entity_type: record[:entity_type],
        entity_id: record[:entity_id]
      }
      
      # Add relevant properties
      if record[:properties]
        props = extract_relevant_properties(record[:properties])
        metadata.merge!(props)
      end
      
      # Add relationship counts
      if record[:relationships]
        metadata[:relationship_count] = record[:relationships].size
        metadata[:relationship_types] = record[:relationships].map { |r| r[:type] }.uniq
      end
      
      metadata
    end
    
    # Extract relevant properties (exclude system fields)
    def self.extract_relevant_properties(properties)
      # Convert Neo4j node to hash if needed
      props = properties.is_a?(Hash) ? properties : properties.to_h
      
      # Filter out system properties
      exclude_keys = [:id, :entity_id, :batch_id, :created_at, :updated_at, :embedding]
      
      props.reject do |key, value|
        exclude_keys.include?(key.to_sym) || 
        key.to_s.start_with?('_') ||
        value.nil? ||
        (value.is_a?(String) && value.empty?) ||
        (value.is_a?(Array) && value.first(100).is_a?(Float))  # Skip embeddings
      end
    end
  end
end