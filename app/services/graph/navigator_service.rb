# frozen_string_literal: true

module Graph
  # Core service for Knowledge Navigator functionality
  # Handles path queries, textization, rights echo, and question answering
  class NavigatorService
    attr_reader :ekn, :driver, :database

    def initialize(ekn:)
      @ekn = ekn
      @database = ekn.neo4j_database_name
      @driver = Connection.instance.driver
      @node_locator = NodeLocator.new(ekn: ekn)
    end

    # Find a node by ID and return its details
    def find_node(node_id)
      @driver.session(database: @database) do |session|
        session.read_transaction do |tx|
          query = <<~CYPHER
            MATCH (n)
            WHERE id(n) = $node_id
            RETURN n, labels(n)[0] as pool
          CYPHER
          
          result = tx.run(query, node_id: node_id.to_i).single
          return nil unless result
          
          node = result['n']
          pool = result['pool']
          
          {
            id: node.id,
            pool: pool,
            repr_text: node.properties['repr_text'] || node.properties['label'] || node.properties['narrative_text'],
            properties: node.properties,
            label: @node_locator.canonical_label_for(node.properties.merge(pool_type: pool))
          }
        end
      end
    end

    # Get all edges for an entity, grouped by canonical verb
    def edges_by_verb_for_entity(node_id, limit_per_direction: 50)
      @driver.session(database: @database) do |session|
        session.read_transaction do |tx|
          # Get outgoing edges (removed batch_id filter to work with any data)
          outgoing_query = <<~CYPHER
            MATCH (source)-[r]->(target)
            WHERE id(source) = $node_id AND type(r) <> 'HAS_RIGHTS'
            RETURN 
              id(r) as edge_id,
              type(r) as verb,
              r as rel,
              'outgoing' as direction,
              labels(source)[0] as source_pool,
              source as source_node,
              labels(target)[0] as target_pool,
              target as target_node
            LIMIT $limit
          CYPHER
          
          # Get incoming edges
          incoming_query = <<~CYPHER
            MATCH (source)-[r]->(target)
            WHERE id(target) = $node_id AND type(r) <> 'HAS_RIGHTS'
            RETURN 
              id(r) as edge_id,
              type(r) as verb,
              r as rel,
              'incoming' as direction,
              labels(source)[0] as source_pool,
              source as source_node,
              labels(target)[0] as target_pool,
              target as target_node
            LIMIT $limit
          CYPHER
          
          outgoing = tx.run(outgoing_query, node_id: node_id.to_i, limit: limit_per_direction).to_a
          incoming = tx.run(incoming_query, node_id: node_id.to_i, limit: limit_per_direction).to_a
          
          all_edges = outgoing + incoming
          
          # Group by canonical verb
          edges_by_verb = {}
          
          all_edges.each do |row|
            verb = row['verb'].downcase
            canonical_verb = VerbPolicy.normalize(verb) || verb
            
            edges_by_verb[canonical_verb] ||= []
            
            rel = row['rel']
            
            edge_data = {
              id: row['edge_id'],
              verb: verb,
              direction: row['direction'],
              status: rel.properties['status'] || 'legacy',
              confidence: rel.properties['confidence'],
              evidence_span: rel.properties['evidence_span'],
              evidence_item_id: rel.properties['evidence_item_id'],
              path_sentence: rel.properties['path_sentence'],
              verified_at: rel.properties['verified_at'],
              verified_by: rel.properties['verified_by'],
              source: format_node_summary(row['source_node'], row['source_pool']),
              target: format_node_summary(row['target_node'], row['target_pool'])
            }
            
            # Add rights echo if available
            if rel.properties['evidence_item_id']
              edge_data[:rights_echo] = fetch_rights_echo(rel.properties['evidence_item_id'])
            end
            
            edges_by_verb[canonical_verb] << edge_data
          end
          
          edges_by_verb
        end
      end
    end

    # Find paths between nodes (1-3 hops) using spec verbs only
    def paths_for_entity(node_id, max_hops: 3)
      @driver.session(database: @database) do |session|
        session.read_transaction do |tx|
          # Build verb list from spec glossary, exclude HAS_RIGHTS
          spec_verbs = EdgeLoader::VERB_GLOSSARY.keys.map(&:to_s).map(&:upcase)
            .reject { |v| v == 'HAS_RIGHTS' }
          
          query = <<~CYPHER
            MATCH path = (start)-[*1..#{max_hops}]-(end)
            WHERE id(start) = $node_id
              AND all(r IN relationships(path) WHERE type(r) IN $verbs AND type(r) <> 'HAS_RIGHTS')
              AND id(end) <> id(start)
            RETURN path
            LIMIT 10
          CYPHER
          
          result = tx.run(query, node_id: node_id.to_i, verbs: spec_verbs)
          
          paths = result.map do |row|
            path = row['path']
            {
              nodes: path.nodes.map { |n| format_node_summary(n, n.labels.first) },
              relationships: path.relationships.map { |r| 
                {
                  type: r.type,
                  status: r.properties['status'],
                  confidence: r.properties['confidence']
                }
              },
              sentence: textize_path(path)
            }
          end
          
          paths
        end
      end
    end

    # Convert a path to a textual sentence following spec rules
    def textize_path(path)
      return "" unless path
      
      segments = []
      nodes = path.nodes
      relationships = path.relationships
      
      nodes.each_with_index do |node, i|
        pool = node.labels.first
        label = @node_locator.canonical_label_for(node.properties.merge(pool_type: pool))
        
        segments << "#{pool}(#{label})"
        
        if i < relationships.length
          rel = relationships[i]
          verb = rel.type.downcase
          segments << "→ #{verb} →"
        end
      end
      
      segments.join(' ')
    end

    # Generate textized path for a single relationship
    def textize_relationship(edge_id)
      @driver.session(database: @database) do |session|
        session.read_transaction do |tx|
          query = <<~CYPHER
            MATCH (source)-[r]->(target)
            WHERE id(r) = $edge_id
            RETURN 
              type(r) as verb,
              labels(source)[0] as source_pool,
              source as source_node,
              labels(target)[0] as target_pool,
              target as target_node
          CYPHER
          
          result = tx.run(query, edge_id: edge_id.to_i).single
          return nil unless result
          
          source_label = @node_locator.canonical_label_for(
            result['source_node'].properties.merge(pool_type: result['source_pool'])
          )
          target_label = @node_locator.canonical_label_for(
            result['target_node'].properties.merge(pool_type: result['target_pool'])
          )
          verb = result['verb'].downcase
          
          # Check if verb has a custom sentence pattern
          verb_config = EdgeLoader::VERB_GLOSSARY[verb.to_sym]
          
          if verb_config && verb_config[:sentence_pattern]
            verb_config[:sentence_pattern]
              .gsub('{source}', "#{result['source_pool']}(#{source_label})")
              .gsub('{target}', "#{result['target_pool']}(#{target_label})")
          else
            "#{result['source_pool']}(#{source_label}) → #{verb} → #{result['target_pool']}(#{target_label})"
          end
        end
      end
    end

    # Fetch rights echo for an evidence item
    def fetch_rights_echo(evidence_item_id)
      return nil unless evidence_item_id
      
      @driver.session(database: @database) do |session|
        session.read_transaction do |tx|
          query = <<~CYPHER
            MATCH (item:ProvenanceAndRights)
            WHERE item.id = $item_id
            RETURN item
          CYPHER
          
          result = tx.run(query, item_id: evidence_item_id).single
          return nil unless result
          
          item = result['item']
          
          {
            publishability: item.properties['publishability'],
            training_eligibility: item.properties['training_eligibility'],
            license: item.properties['license'],
            consent_status: item.properties['consent_status'],
            attribution: item.properties['attribution']
          }
        end
      end
    end

    # Answer a question by finding relevant paths
    def answer(question)
      # This is a simplified implementation
      # In production, would use fine-tuned model or more sophisticated routing
      
      # Extract potential entities from question (simplified)
      entities = find_entities_in_question(question)
      
      return { 
        path_sentence: nil,
        citations: [],
        rights_echo: nil,
        fallback: "No entities found in question. Please be more specific.",
        mode_hints: [:table]
      } if entities.empty?
      
      # Find paths between entities
      if entities.length >= 2
        path = find_path_between(entities[0][:id], entities[1][:id])
        if path
          return format_answer_with_path(path, question)
        end
      end
      
      # Try single entity exploration
      if entities.length >= 1
        paths = paths_for_entity(entities[0][:id], max_hops: 2)
        if paths.any?
          return format_answer_with_path(paths.first, question)
        end
      end
      
      {
        path_sentence: nil,
        citations: [],
        rights_echo: nil,
        fallback: "Unable to find relevant paths. More data needed for: #{question}",
        mode_hints: [:table]
      }
    end

    # Run answerability test on top-50 questions
    def answerability_run(questions:)
      results = {
        total: questions.length,
        answered: 0,
        failed: [],
        answers: []
      }
      
      questions.each do |q|
        answer = answer(q)
        
        if answer[:path_sentence]
          results[:answered] += 1
          results[:answers] << {
            question: q,
            answer: answer[:path_sentence],
            citations: answer[:citations].length
          }
        else
          results[:failed] << {
            question: q,
            reason: answer[:fallback]
          }
        end
      end
      
      results[:answerability_rate] = (results[:answered].to_f / results[:total] * 100).round(1)
      results
    end

    private

    def format_node_summary(node, pool)
      {
        id: node.id,
        pool: pool,
        label: @node_locator.canonical_label_for(node.properties.merge(pool_type: pool)),
        repr_text: node.properties['repr_text']
      }
    end

    def find_entities_in_question(question)
      # Simplified entity extraction - OPTIMIZED to avoid hanging
      # In production, would use fine-tuned model or NER
      
      @driver.session(database: @database) do |session|
        session.read_transaction do |tx|
          # Extract the most important keywords (limit to 3 to avoid too many queries)
          keywords = question.downcase.split(/\s+/)
            .select { |w| w.length > 4 && !%w[what which where when that this these those does embody relate].include?(w) }
            .first(3)
          
          return [] if keywords.empty?
          
          # Query for all keywords and combine results
          query = <<~CYPHER
            MATCH (n)
            WHERE n.label IS NOT NULL 
              AND toLower(n.label) CONTAINS toLower($keyword)
            RETURN n, labels(n)[0] as pool
            LIMIT 3
          CYPHER
          
          entities = []
          seen_ids = Set.new
          
          # Search for each keyword and collect unique entities
          keywords.each do |keyword|
            result = tx.run(query, keyword: keyword)
            result.each do |row|
              entity_id = row['n'].id
              unless seen_ids.include?(entity_id)
                seen_ids << entity_id
                entities << {
                  id: entity_id,
                  pool: row['pool'],
                  label: @node_locator.canonical_label_for(row['n'].properties.merge(pool_type: row['pool']))
                }
              end
            end
            break if entities.length >= 3 # Limit total entities
          end
          
          entities
        end
      end
    end

    def find_path_between(start_id, end_id, max_hops: 3)
      @driver.session(database: @database) do |session|
        session.read_transaction do |tx|
          # Only use spec verbs, explicitly exclude HAS_RIGHTS
          spec_verbs = EdgeLoader::VERB_GLOSSARY.keys.map(&:to_s).map(&:upcase).reject { |v| v == 'HAS_RIGHTS' }
          
          query = <<~CYPHER
            MATCH path = shortestPath((start)-[*1..#{max_hops}]-(end))
            WHERE id(start) = $start_id 
              AND id(end) = $end_id
              AND all(r IN relationships(path) WHERE type(r) IN $verbs AND type(r) <> 'HAS_RIGHTS')
            RETURN path
          CYPHER
          
          result = tx.run(query, start_id: start_id, end_id: end_id, verbs: spec_verbs)
          first_result = result.first
          first_result ? first_result['path'] : nil
        end
      end
    end

    def format_answer_with_path(path, question)
      sentence = textize_path(path) if path.respond_to?(:nodes)
      sentence ||= path[:sentence] if path.is_a?(Hash)
      
      # Extract citations from path edges
      citations = []
      if path.respond_to?(:relationships)
        path.relationships.each do |rel|
          if rel.properties['evidence_item_id']
            citations << {
              item_id: rel.properties['evidence_item_id'],
              snippet: rel.properties['evidence_span']
            }
          end
        end
      end
      
      # Get rights echo from first citation
      rights_echo = nil
      if citations.any?
        rights_echo = fetch_rights_echo(citations.first[:item_id])
      end
      
      {
        path_sentence: sentence,
        citations: citations,
        rights_echo: rights_echo,
        fallback: nil,
        mode_hints: [:table, :graph]
      }
    end
  end
end