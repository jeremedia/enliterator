# frozen_string_literal: true

module Graph
  # Manages the two-tier edge model: Candidate vs Verified relationships
  # Handles provenance tracking and path textization for verified edges
  class RelationshipManager
    attr_reader :ekn, :driver, :database

    def initialize(ekn:)
      @ekn = ekn
      @database = ekn.neo4j_database_name
      @driver = Connection.instance.driver
    end

    # Promote a candidate relationship to verified status
    def promote_to_verified(relationship_id, promoted_by: 'system', reason: nil)
      @driver.session(database: @database) do |session|
        session.write_transaction do |tx|
          query = <<~CYPHER
            MATCH ()-[r]->()
            WHERE id(r) = $rel_id AND r.status = 'candidate'
            SET r.status = 'verified',
                r.verified_at = datetime(),
                r.verified_by = $promoted_by,
                r.verification_reason = $reason
            RETURN r
          CYPHER
          
          result = tx.run(query, 
            rel_id: relationship_id,
            promoted_by: promoted_by,
            reason: reason
          )
          
          rel = result.single
          if rel
            # Generate path sentence for verified edge
            generate_path_sentence(tx, relationship_id)
            true
          else
            false
          end
        end
      end
    end

    # Reject a candidate relationship
    def reject_candidate(relationship_id, rejected_by: 'system', reason: nil)
      @driver.session(database: @database) do |session|
        session.write_transaction do |tx|
          query = <<~CYPHER
            MATCH ()-[r]->()
            WHERE id(r) = $rel_id AND r.status = 'candidate'
            DELETE r
            RETURN count(r) as deleted
          CYPHER
          
          result = tx.run(query, rel_id: relationship_id)
          result.single['deleted'] > 0
        end
      end
    end

    # Get all candidate relationships for review
    def list_candidates(limit: 50)
      @driver.session(database: @database) do |session|
        session.read_transaction do |tx|
          query = <<~CYPHER
            MATCH (source)-[r]->(target)
            WHERE r.status = 'candidate'
            RETURN 
              id(r) as id,
              type(r) as verb,
              labels(source)[0] as source_pool,
              source as source_node,
              labels(target)[0] as target_pool,
              target as target_node,
              r.confidence as confidence,
              r.evidence_span as evidence,
              r.discovered_by as discovered_by,
              r.cluster_strategy as strategy,
              r.discovered_at as discovered_at
            ORDER BY r.confidence DESC
            LIMIT $limit
          CYPHER
          
          result = tx.run(query, limit: limit)
          result.map do |row|
            {
              id: row['id'],
              verb: row['verb'],
              source: extract_node_summary(row['source_node'], row['source_pool']),
              target: extract_node_summary(row['target_node'], row['target_pool']),
              confidence: row['confidence'],
              evidence: row['evidence'],
              discovered_by: row['discovered_by'],
              strategy: row['strategy'],
              discovered_at: row['discovered_at']
            }
          end
        end
      end
    end

    # Get verified relationships with path sentences
    def list_verified(limit: 50)
      @driver.session(database: @database) do |session|
        session.read_transaction do |tx|
          query = <<~CYPHER
            MATCH (source)-[r]->(target)
            WHERE r.status = 'verified'
            RETURN 
              id(r) as id,
              type(r) as verb,
              labels(source)[0] as source_pool,
              source as source_node,
              labels(target)[0] as target_pool,
              target as target_node,
              r.confidence as confidence,
              r.path_sentence as path_sentence,
              r.verified_by as verified_by,
              r.verified_at as verified_at
            ORDER BY r.verified_at DESC
            LIMIT $limit
          CYPHER
          
          result = tx.run(query, limit: limit)
          result.map do |row|
            {
              id: row['id'],
              verb: row['verb'],
              source: extract_node_summary(row['source_node'], row['source_pool']),
              target: extract_node_summary(row['target_node'], row['target_pool']),
              confidence: row['confidence'],
              path_sentence: row['path_sentence'],
              verified_by: row['verified_by'],
              verified_at: row['verified_at']
            }
          end
        end
      end
    end

    # Generate metrics for two-tier edges
    def edge_metrics
      @driver.session(database: @database) do |session|
        session.read_transaction do |tx|
          # Count by status
          status_query = <<~CYPHER
            MATCH ()-[r]->()
            WHERE type(r) <> 'HAS_RIGHTS'
            RETURN r.status as status, count(r) as count
          CYPHER
          
          status_counts = tx.run(status_query).map { |r| [r['status'] || 'legacy', r['count']] }.to_h
          
          # Count by verb for verified
          verb_query = <<~CYPHER
            MATCH ()-[r]->()
            WHERE r.status = 'verified'
            RETURN type(r) as verb, count(r) as count
            ORDER BY count DESC
          CYPHER
          
          verb_counts = tx.run(verb_query).map { |r| [r['verb'], r['count']] }.to_h
          
          # Average confidence by status
          confidence_query = <<~CYPHER
            MATCH ()-[r]->()
            WHERE r.confidence IS NOT NULL
            RETURN r.status as status, avg(r.confidence) as avg_confidence
          CYPHER
          
          confidence_by_status = tx.run(confidence_query).map { |r| [r['status'] || 'legacy', r['avg_confidence']] }.to_h
          
          {
            total: status_counts.values.sum,
            by_status: status_counts,
            verified_verbs: verb_counts,
            average_confidence: confidence_by_status,
            verification_rate: calculate_rate(status_counts['verified'], status_counts.values.sum)
          }
        end
      end
    end

    private

    def generate_path_sentence(tx, relationship_id)
      # Get the relationship and its nodes
      query = <<~CYPHER
        MATCH (source)-[r]->(target)
        WHERE id(r) = $rel_id
        RETURN 
          type(r) as verb,
          labels(source)[0] as source_pool,
          source as source_node,
          labels(target)[0] as target_pool,
          target as target_node
      CYPHER
      
      result = tx.run(query, rel_id: relationship_id).single
      return unless result
      
      # Build path sentence using canonical names
      locator = NodeLocator.new(ekn: @ekn)
      # Include pool_type in properties for proper label extraction
      source_props = result['source_node'].properties.merge(pool_type: result['source_pool'])
      target_props = result['target_node'].properties.merge(pool_type: result['target_pool'])
      source_label = locator.canonical_label_for(source_props)
      target_label = locator.canonical_label_for(target_props)
      verb = result['verb'].downcase
      
      # Check if verb has a custom sentence pattern in glossary
      verb_config = EdgeLoader::VERB_GLOSSARY[verb.to_sym]
      
      path_sentence = if verb_config && verb_config[:sentence_pattern]
        # Use custom pattern if available
        verb_config[:sentence_pattern]
          .gsub('{source}', "#{result['source_pool']}(#{source_label})")
          .gsub('{target}', "#{result['target_pool']}(#{target_label})")
      else
        # Default pattern: Pool(name) → verb → Pool(name)
        "#{result['source_pool']}(#{source_label}) → #{verb} → #{result['target_pool']}(#{target_label})"
      end
      
      # Store the path sentence
      update_query = <<~CYPHER
        MATCH ()-[r]->()
        WHERE id(r) = $rel_id
        SET r.path_sentence = $sentence
      CYPHER
      
      tx.run(update_query, rel_id: relationship_id, sentence: path_sentence)
    end

    def extract_node_summary(node, pool_type)
      locator = NodeLocator.new(ekn: @ekn)
      # Include pool_type in properties for proper label extraction
      props_with_pool = node.properties.merge(pool_type: pool_type)
      {
        pool: pool_type,
        label: locator.canonical_label_for(props_with_pool),
        id: node.id
      }
    end

    def calculate_rate(numerator, denominator)
      return 0 if denominator == 0
      (numerator.to_f / denominator * 100).round(1)
    end
  end
end