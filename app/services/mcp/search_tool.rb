# frozen_string_literal: true

# MCP Search Tool for Enliterator
#
# Required by ChatGPT/Deep Research integration
# Returns array of search results with id, title, text snippet, and url
#
# This tool searches the Neo4j knowledge graph for entities matching
# a natural language query, using both keyword and semantic search
#
module Mcp
  class SearchTool
    # ChatGPT requires exactly this response format
    # Arguments: query (string), ekn (optional EKN object)
    # Returns: { results: [ { id, title, text, url } ] }
    def self.call(query:, ekn: nil)
      return { results: [] } if query.blank?
      
      # Use provided EKN or fallback to meta-enliterator
      ekn = ekn || Ekn.find_by(slug: 'meta-enliterator') || Ekn.first
      return { results: [] } unless ekn
      
      Rails.logger.info "MCP SearchTool: query='#{query}' for EKN #{ekn.slug}"
      
      # Use our existing search infrastructure
      search_tool = Mcp::Tools::SimpleSearchTool.new(ekn: ekn)
      search_result = search_tool.execute(
        query: query,
        top_k: 10,  # Reasonable default for ChatGPT
        require_rights: 'public'  # Only return public data
      )
      
      # Transform to ChatGPT required format
      results = []
      
      if search_result[:items]&.any?
        search_result[:items].each do |item|
          # Build URL for this entity (different for PostgreSQL vs Neo4j)
          entity_url = build_entity_url(ekn, item[:entity_id], item[:source])
          
          # Create text snippet
          text_snippet = build_text_snippet(item)
          
          results << {
            id: "#{item[:source]}_#{item[:entity_id]}",  # Prefix with source for uniqueness
            title: item[:entity_name] || "Entity #{item[:entity_id]}",
            text: text_snippet,
            url: entity_url
          }
        end
      end
      
      # Return in exact format required by ChatGPT
      { results: results }
      
    rescue => e
      Rails.logger.error "MCP SearchTool error: #{e.message}"
      Rails.logger.error e.backtrace.first(10).join("\n")
      
      # Always return valid structure even on error
      { 
        results: [],
        error: "Search failed: #{e.message}"
      }
    end
    
    private
    
    # Build a URL for the entity
    def self.build_entity_url(ekn, entity_id, source = 'neo4j')
      # In production, use your actual domain
      base_url = ENV['APP_BASE_URL'] || 'https://e.dev.domt.app'
      
      case source
      when 'postgresql'
        "#{base_url}/ekns/#{ekn.slug}/characters/#{entity_id}"
      else
        "#{base_url}/ekns/#{ekn.slug}/entities/#{entity_id}"
      end
    end
    
    # Build text snippet from item data
    def self.build_text_snippet(item)
      parts = []
      
      # Add entity type if available
      if item[:entity_type]
        type_display = item[:entity_type]
        type_display += " (#{item[:character_role_type]})" if item[:character_role_type]
        parts << "Type: #{type_display}"
      end
      
      # Add content or repr_text
      if item[:content].present?
        content = item[:content]
        # Truncate to reasonable length for snippet
        content = content[0..200] + "..." if content.length > 200
        parts << content
      end
      
      # Add path preview if available
      if item[:path_preview].present?
        parts << "Related: #{item[:path_preview]}"
      end
      
      # Add connection count if available
      if item[:connections] && item[:connections] > 0
        parts << "#{item[:connections]} connections"
      end
      
      parts.join(" | ")
    end
  end
end