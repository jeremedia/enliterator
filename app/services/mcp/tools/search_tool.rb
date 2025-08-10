# frozen_string_literal: true

module Mcp
  module Tools
    # MCP Search Tool - Semantic and graph search with rights filtering
    class SearchTool
      attr_reader :ekn, :embedding_service, :navigator
      
      def initialize(ekn:)
        @ekn = ekn
        # Use the most recent batch for this EKN
        batch_id = ekn.ingest_batches.last&.id
        @embedding_service = Neo4j::EmbeddingService.new(batch_id)
        @navigator = Graph::NavigatorService.new(ekn: ekn)
      end
      
      def execute(query:, top_k: 10, pools: nil, require_rights: 'public', diversify_by_pool: true)
        Rails.logger.info "SearchTool executing: query='#{query}', pools=#{pools}, rights=#{require_rights}"
        
        # Step 1: Semantic search via Neo4j GenAI
        semantic_results = perform_semantic_search(query, pools, top_k)
        
        # Step 2: Enhance with graph context
        enhanced_results = enhance_with_graph_context(semantic_results)
        
        # Step 3: Apply rights filtering
        filtered_results = filter_by_rights(enhanced_results, require_rights)
        
        # Step 4: Diversify results if requested
        final_results = if diversify_by_pool
          diversify_results(filtered_results, top_k)
        else
          filtered_results.first(top_k)
        end
        
        # Step 5: Format response
        {
          items: format_results(final_results),
          meta: build_metadata(semantic_results, final_results),
          query: query,
          tool: 'search'
        }
      rescue => e
        Rails.logger.error "SearchTool error: #{e.message}"
        Rails.logger.error e.backtrace.first(10).join("\n")
        
        {
          items: [],
          meta: { error: e.message },
          query: query,
          tool: 'search'
        }
      end
      
      alias call execute
      
      private
      
      def perform_semantic_search(query, pools, limit)
        # Use Neo4j GenAI embeddings for semantic search
        results = @embedding_service.semantic_search(
          query,
          limit: limit * 2,  # Get extra for filtering
          pools: pools
        )
        
        Rails.logger.info "Semantic search returned #{results.size} results"
        results
      end
      
      def enhance_with_graph_context(results)
        results.map do |result|
          # Get 1-hop paths to show connections
          paths = @navigator.paths_for_entity(
            result['entity_id'].to_i,
            max_hops: 1
          )
          
          # Get edges by verb for this entity
          edges = @navigator.edges_by_verb_for_entity(
            result['entity_id'].to_i,
            limit_per_direction: 5
          )
          
          result.merge(
            'connections_count' => paths.size,
            'path_preview' => paths.first&.dig(:sentence),
            'verb_summary' => edges.keys.sort,
            'paths' => paths.first(3)  # Include top 3 paths
          )
        end
      rescue => e
        Rails.logger.error "Error enhancing with graph context: #{e.message}"
        results
      end
      
      def filter_by_rights(results, rights_level)
        return results if rights_level == 'any'
        
        results.select do |result|
          # Find the IngestItem for this entity
          item = IngestItem.find_by(
            pool_item_type: result['entity_type'],
            pool_item_id: result['entity_id']
          )
          
          next false unless item
          
          # Check rights
          if rights_level == 'public'
            item.publishable
          elsif rights_level == 'internal'
            item.training_eligible
          else
            true
          end
        end
      end
      
      def diversify_results(results, limit)
        diverse = []
        seen_pools = Set.new
        
        # First pass: one from each unique pool
        results.each do |result|
          pool = result['entity_type']
          unless seen_pools.include?(pool)
            diverse << result
            seen_pools << pool
            break if diverse.size >= limit
          end
        end
        
        # Second pass: fill remaining slots with best scores
        remaining = results - diverse
        diverse + remaining.first(limit - diverse.size)
      end
      
      def format_results(results)
        results.map do |result|
          {
            entity_id: result['entity_id'],
            entity_type: result['entity_type'],
            entity_name: result['entity_name'],
            content: result['content'] || result['repr_text'],
            similarity: result['similarity'].to_f.round(3),
            connections: result['connections_count'] || 0,
            path_preview: result['path_preview'],
            verb_summary: result['verb_summary'] || [],
            paths: result['paths'] || []
          }
        end
      end
      
      def build_metadata(semantic_results, final_results)
        pools_count = final_results.group_by { |r| r['entity_type'] }
                                   .transform_values(&:size)
        
        {
          total_before_filter: semantic_results.size,
          total_after_filter: final_results.size,
          pools_represented: pools_count.keys,
          pool_counts: pools_count,
          search_method: 'neo4j_genai_semantic'
        }
      end
    end
  end
end