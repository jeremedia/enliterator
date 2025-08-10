# frozen_string_literal: true

module Mcp
  module Tools
    # Simplified search tool that works without vector indexes
    class SimpleSearchTool
      attr_reader :ekn, :navigator
      
      def initialize(ekn:)
        @ekn = ekn
        @navigator = Graph::NavigatorService.new(ekn: ekn)
        @driver = Graph::Connection.instance.driver
      end
      
      def execute(query:, top_k: 10, pools: nil, require_rights: 'public')
        Rails.logger.info "SimpleSearchTool: query='#{query}', pools=#{pools}"
        
        # For now, do keyword search in Neo4j
        results = keyword_search(query, pools, top_k * 2)
        
        # Enhance with graph context
        enhanced = enhance_results(results)
        
        # Apply rights filtering
        filtered = filter_by_rights(enhanced, require_rights)
        
        # Take top k
        final = filtered.first(top_k)
        
        {
          items: final,
          meta: {
            total_found: results.size,
            total_after_filter: filtered.size,
            method: 'keyword_search'
          },
          query: query,
          tool: 'simple_search'
        }
      end
      
      private
      
      def keyword_search(query, pools, limit)
        session = @driver.session(database: @ekn.neo4j_database_name)
        
        # Build pool filter
        pool_filter = if pools && pools.any?
          "AND (" + pools.map { |p| "n:#{p}" }.join(" OR ") + ")"
        else
          ""
        end
        
        # Search for nodes containing the query text
        cypher = <<~CYPHER
          MATCH (n)
          WHERE (n.label IS NOT NULL AND toLower(n.label) CONTAINS toLower($query))
             OR (n.repr_text IS NOT NULL AND toLower(n.repr_text) CONTAINS toLower($query))
             #{pool_filter}
          RETURN 
            id(n) as entity_id,
            labels(n)[0] as entity_type,
            n.label as entity_name,
            n.repr_text as content,
            CASE 
              WHEN toLower(n.label) CONTAINS toLower($query) THEN 1.0
              ELSE 0.5
            END as relevance
          ORDER BY relevance DESC
          LIMIT #{limit}
        CYPHER
        
        result = session.run(cypher, query: query)
        
        results = result.map do |r|
          {
            entity_id: r[:entity_id],
            entity_type: r[:entity_type],
            entity_name: r[:entity_name] || "Unnamed #{r[:entity_type]}",
            content: r[:content] || r[:entity_name],
            similarity: r[:relevance]
          }
        end
        
        session.close
        results
      rescue => e
        Rails.logger.error "Keyword search failed: #{e.message}"
        session&.close
        []
      end
      
      def enhance_results(results)
        results.map do |result|
          # Get basic info about connections
          paths = @navigator.paths_for_entity(result[:entity_id], max_hops: 1) rescue []
          
          result.merge(
            connections: paths.size,
            path_preview: paths.first&.dig(:sentence)
          )
        end
      end
      
      def filter_by_rights(results, rights_level)
        return results if rights_level == 'any'
        
        # For now, return all results (would check IngestItem in production)
        results
      end
    end
  end
end