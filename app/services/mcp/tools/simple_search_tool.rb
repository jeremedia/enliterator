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
        
        # Search both Neo4j and all PostgreSQL entity types
        neo4j_results = keyword_search(query, pools, top_k * 2)
        postgres_results = search_all_postgres_entities(query, pools, top_k)
        
        # Combine results
        results = neo4j_results + postgres_results
        
        # If no results with full phrase, try individual words
        if results.empty? && query.include?(' ')
          Rails.logger.info "No results for full phrase, trying individual words"
          words = query.split(/\s+/)
          all_results = []
          
          words.each do |word|
            neo4j_word_results = keyword_search(word, pools, top_k)
            postgres_word_results = search_all_postgres_entities(word, pools, top_k)
            all_results.concat(neo4j_word_results + postgres_word_results)
          end
          
          # Deduplicate and sort by relevance
          results = all_results.uniq { |r| "#{r[:source]}_#{r[:entity_id]}" }
                              .sort_by { |r| -r[:similarity] }
                              .first(top_k * 2)
        end
        
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
          WHERE ((n.label IS NOT NULL AND toLower(n.label) CONTAINS toLower($query))
             OR (n.repr_text IS NOT NULL AND toLower(n.repr_text) CONTAINS toLower($query)))
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
        
        Rails.logger.info "SimpleSearchTool Cypher query: #{cypher}"
        Rails.logger.info "Query param: #{query}, Pools: #{pools.inspect}"
        
        result = session.run(cypher, query: query)
        
        results = result.map do |r|
          {
            entity_id: r[:entity_id],
            entity_type: r[:entity_type],
            entity_name: r[:entity_name] || "Unnamed #{r[:entity_type]}",
            content: r[:content] || r[:entity_name],
            similarity: r[:relevance],
            source: 'neo4j'
          }
        end
        
        session.close
        results
      rescue => e
        Rails.logger.error "Keyword search failed: #{e.message}"
        session&.close
        []
      end

      def search_all_postgres_entities(query, pools, limit)
        Rails.logger.info "Searching PostgreSQL entities for query: '#{query}', pools: #{pools.inspect}"
        
        # Configuration for all hidden entity types
        entity_configs = [
          { model: Character, pool: 'Actor', search_fields: [:label, :biography, :title],
            name_method: :display_name, content_method: :full_description, 
            prefix: 'char_', extra_data: ->(record) { { character_role_type: record.role_type } } },
          { model: Space, pool: 'Spatial', search_fields: [:label, :description, :region, :country],
            name_method: :label, content_method: :description,
            prefix: 'space_' },
          { model: Symbolic, pool: 'Emanation', search_fields: [:label, :meaning, :cultural_context],
            name_method: :label, content_method: :meaning,
            prefix: 'sym_' },
          { model: TimeEntity, pool: 'Method', search_fields: [:label, :description],
            name_method: :label, content_method: :description,
            prefix: 'time_' },
          { model: Lifecycle, pool: 'Evolutionary', search_fields: [:label, :description],
            name_method: :label, content_method: :description,
            prefix: 'life_' },
          { model: Relator, pool: 'Relational', search_fields: [:label, :description],
            name_method: :label, content_method: :description,
            prefix: 'rel_' }
        ]
        
        # Filter configs by requested pools
        if pools && pools.any?
          entity_configs = entity_configs.select { |config| pools.include?(config[:pool]) }
        end
        
        all_results = []
        
        entity_configs.each do |config|
          Rails.logger.info "Searching #{config[:model]} for #{config[:pool]} pool"
          
          # Build search conditions for all fields
          conditions = config[:search_fields].map { |field| "#{field} ILIKE ?" }.join(' OR ')
          params = config[:search_fields].map { "%#{query}%" }
          
          records = config[:model].where(conditions, *params).limit(limit / entity_configs.size + 1)
          
          results = records.map do |record|
            # Calculate relevance based on field priority
            relevance = 0.6 # Base relevance
            config[:search_fields].each_with_index do |field, index|
              field_value = record.try(field)
              if field_value&.downcase&.include?(query.downcase)
                relevance = [1.0 - (index * 0.2), 0.3].max # First field = 1.0, second = 0.8, etc.
                break
              end
            end
            
            result = {
              entity_id: "#{config[:prefix]}#{record.id}",
              entity_type: config[:pool],
              entity_name: record.try(config[:name_method]) || record.label,
              content: record.try(config[:content_method]) || record.label,
              similarity: relevance,
              source: 'postgresql'
            }
            
            # Add extra data if configured
            if config[:extra_data]
              result.merge!(config[:extra_data].call(record))
            end
            
            result
          end
          
          all_results.concat(results)
          Rails.logger.info "Found #{results.size} #{config[:pool]} matches"
        end
        
        # Sort by relevance and limit
        all_results.sort_by { |r| -r[:similarity] }.first(limit)
      rescue => e
        Rails.logger.error "PostgreSQL entity search failed: #{e.message}"
        []
      end
      
      def enhance_results(results)
        results.map do |result|
          if result[:source] == 'postgresql'
            # PostgreSQL Character entities - add role type info instead of connections
            result.merge(
              connections: 0,
              path_preview: "Arctic #{result[:character_role_type]&.humanize || 'Character'}"
            )
          else
            # Neo4j entities - get basic info about connections
            paths = @navigator.paths_for_entity(result[:entity_id], max_hops: 1) rescue []
            
            result.merge(
              connections: paths.size,
              path_preview: paths.first&.dig(:sentence)
            )
          end
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