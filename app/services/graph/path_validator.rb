# frozen_string_literal: true

module Graph
  # Validates that discovered relationships form valid navigable paths
  # according to the Enliterator specification.
  #
  # Key validations:
  # 1. Relationships use verbs from the closed Relation Verb Glossary
  # 2. Paths can be textized into natural language sentences
  # 3. Entities have canonical names for path narration
  # 4. Pool type constraints are respected for each verb
  # 5. Paths form meaningful cross-boundary connections
  #
  class PathValidator
    attr_reader :ekn, :batch, :errors, :warnings
    
    def initialize(ekn:, batch: nil)
      @ekn = ekn
      @batch = batch
      @driver = Graph::Connection.instance.driver
      @errors = []
      @warnings = []
    end
    
    # Validate all relationships in the graph
    def validate_all_relationships
      @errors.clear
      @warnings.clear
      
      Rails.logger.info "Validating relationships for EKN: #{@ekn.name}"
      
      @driver.session(database: @ekn.neo4j_database_name) do |session|
        session.read_transaction do |tx|
          validate_relationship_verbs(tx)
          validate_pool_constraints(tx)
          validate_canonical_names(tx)
          validate_path_connectivity(tx)
        end
      end
      
      {
        valid: @errors.empty?,
        errors: @errors,
        warnings: @warnings,
        summary: build_validation_summary
      }
    end
    
    # Validate a specific path through the graph
    def validate_path(node_ids)
      return { valid: false, error: "Path must have at least 2 nodes" } if node_ids.size < 2
      
      path_errors = []
      path_segments = []
      
      @driver.session(database: @ekn.neo4j_database_name) do |session|
        session.read_transaction do |tx|
          # Validate each segment of the path
          node_ids.each_cons(2) do |source_id, target_id|
            segment = validate_path_segment(tx, source_id, target_id)
            
            if segment[:valid]
              path_segments << segment
            else
              path_errors << segment[:error]
            end
          end
          
          # If all segments valid, generate textized path
          if path_errors.empty?
            textized = textize_path(tx, path_segments)
            return {
              valid: true,
              path_segments: path_segments,
              textized_path: textized,
              canonical_path: build_canonical_path(tx, node_ids)
            }
          end
        end
      end
      
      {
        valid: false,
        errors: path_errors
      }
    end
    
    # Textize a path into natural language
    def textize_path(tx, path_segments)
      sentences = []
      
      path_segments.each do |segment|
        source_label = segment[:source_label]
        target_label = segment[:target_label]
        verb = segment[:verb]
        
        # Build natural language sentence
        sentence = case verb
        when 'embodies'
          "The idea '#{source_label}' embodies itself in the manifestation '#{target_label}'"
        when 'elicits'
          "The manifestation '#{target_label}' elicits the experience from #{segment[:target_agent] || 'participants'}"
        when 'influences'
          "#{source_label} influences #{target_label}"
        when 'refines'
          "#{source_label} refines the idea '#{target_label}'"
        when 'located_at'
          "#{source_label} is located at #{target_label}"
        when 'validates'
          "The experience '#{source_label}' validates the practical approach '#{target_label}'"
        when 'codifies'
          "The idea '#{source_label}' codifies into the practical method '#{target_label}'"
        else
          # Generic textization
          "#{source_label} #{verb.humanize.downcase} #{target_label}"
        end
        
        sentences << sentence
      end
      
      sentences.join('. ') + '.'
    end
    
    private
    
    # Validate that all relationships use verbs from the glossary
    def validate_relationship_verbs(tx)
      query = <<~CYPHER
        MATCH ()-[r]->()
        WHERE NOT type(r) IN $allowed_verbs
        RETURN type(r) as verb, count(r) as count
        ORDER BY count DESC
      CYPHER
      
      allowed_verbs = EdgeLoader::VERB_GLOSSARY.keys.map(&:upcase) + ['HAS_RIGHTS']
      
      result = tx.run(query, allowed_verbs: allowed_verbs)
      
      result.each do |record|
        verb = record['verb']
        count = record['count']
        
        @errors << "Invalid relationship verb '#{verb}' used #{count} times (not in Relation Verb Glossary)"
      end
    end
    
    # Validate pool type constraints for relationships
    def validate_pool_constraints(tx)
      EdgeLoader::VERB_GLOSSARY.each do |verb, constraints|
        next if constraints[:symmetric] # Skip symmetric relationships
        
        # Build query to check pool constraints
        source_pools = Array(constraints[:source])
        target_pools = Array(constraints[:target])
        
        next if source_pools.include?('*') && target_pools.include?('*')
        
        query = build_constraint_query(verb, source_pools, target_pools)
        
        result = tx.run(query)
        violations = result.single['violations']
        
        if violations > 0
          @errors << "Pool constraint violation: #{violations} '#{verb}' relationships have wrong source/target pools"
        end
      end
    end
    
    def build_constraint_query(verb, source_pools, target_pools)
      source_check = if source_pools.include?('*')
        "true"
      else
        "NOT any(label IN labels(source) WHERE label IN $source_pools)"
      end
      
      target_check = if target_pools.include?('*')
        "true"
      else
        "NOT any(label IN labels(target) WHERE label IN $target_pools)"
      end
      
      <<~CYPHER
        MATCH (source)-[r:#{verb.upcase}]->(target)
        WHERE #{source_check} OR #{target_check}
        RETURN count(r) as violations
      CYPHER
    end
    
    # Validate that entities have canonical names
    def validate_canonical_names(tx)
      query = <<~CYPHER
        MATCH (n)
        WHERE NOT n:ProvenanceAndRights
          AND NOT n:Lexicon
          AND (n.label IS NULL OR trim(n.label) = '')
        RETURN labels(n)[0] as pool, count(n) as count
      CYPHER
      
      result = tx.run(query)
      
      result.each do |record|
        pool = record['pool']
        count = record['count']
        
        @warnings << "#{count} #{pool} entities missing canonical names (label field)"
      end
    end
    
    # Validate path connectivity and identify islands
    def validate_path_connectivity(tx)
      # Find disconnected components
      query = <<~CYPHER
        MATCH (n)
        WHERE NOT n:ProvenanceAndRights
          AND NOT n:Lexicon
          AND NOT (n)-[]-()
        RETURN labels(n)[0] as pool, count(n) as isolated_count
      CYPHER
      
      result = tx.run(query)
      
      total_isolated = 0
      result.each do |record|
        pool = record['pool']
        count = record['isolated_count']
        total_isolated += count
        
        @warnings << "#{count} isolated #{pool} entities with no relationships"
      end
      
      if total_isolated > 0
        # Check if this is a significant portion
        total_query = <<~CYPHER
          MATCH (n)
          WHERE NOT n:ProvenanceAndRights
            AND NOT n:Lexicon
          RETURN count(n) as total
        CYPHER
        
        total_result = tx.run(total_query)
        total_nodes = total_result.single['total']
        
        isolation_ratio = total_isolated.to_f / total_nodes
        if isolation_ratio > 0.3
          @errors << "High isolation ratio: #{(isolation_ratio * 100).round}% of nodes have no relationships"
        end
      end
    end
    
    # Validate a single path segment
    def validate_path_segment(tx, source_id, target_id)
      query = <<~CYPHER
        MATCH (source)-[r]->(target)
        WHERE id(source) = $source_id AND id(target) = $target_id
        RETURN source, target, type(r) as verb, 
               properties(r) as props,
               labels(source) as source_labels,
               labels(target) as target_labels
      CYPHER
      
      result = tx.run(query, source_id: source_id, target_id: target_id)
      record = result.single
      
      unless record
        return {
          valid: false,
          error: "No relationship found between nodes #{source_id} and #{target_id}"
        }
      end
      
      verb = record['verb'].downcase
      source_pools = record['source_labels']
      target_pools = record['target_labels']
      
      # Validate verb is in glossary
      unless EdgeLoader::VERB_GLOSSARY.key?(verb) || verb == 'has_rights'
        return {
          valid: false,
          error: "Invalid verb '#{verb}' not in Relation Verb Glossary"
        }
      end
      
      # Get canonical names
      source = record['source']
      target = record['target']
      
      {
        valid: true,
        verb: verb,
        source_id: source_id,
        target_id: target_id,
        source_label: source['label'] || source['name'] || "Unknown",
        target_label: target['label'] || target['name'] || "Unknown",
        source_pools: source_pools,
        target_pools: target_pools,
        confidence: record['props']['confidence'] || 1.0
      }
    end
    
    # Build canonical path representation
    def build_canonical_path(tx, node_ids)
      nodes = []
      
      node_ids.each do |node_id|
        query = <<~CYPHER
          MATCH (n)
          WHERE id(n) = $node_id
          RETURN n.label as label, labels(n) as pools
        CYPHER
        
        result = tx.run(query, node_id: node_id)
        record = result.single
        
        if record
          pool = record['pools'].first
          label = record['label'] || "Unknown"
          nodes << "#{pool}(#{label})"
        end
      end
      
      nodes.join(" → ")
    end
    
    def build_validation_summary
      total_errors = @errors.size
      total_warnings = @warnings.size
      
      summary = []
      
      if total_errors == 0
        summary << "✅ All relationships valid"
      else
        summary << "❌ #{total_errors} validation errors found"
      end
      
      if total_warnings > 0
        summary << "⚠️ #{total_warnings} warnings"
      end
      
      # Get relationship statistics
      @driver.session(database: @ekn.neo4j_database_name) do |session|
        stats_query = <<~CYPHER
          MATCH ()-[r]->()
          WHERE type(r) <> 'HAS_RIGHTS'
          WITH type(r) as verb, count(r) as count
          RETURN sum(count) as total_relationships,
                 count(distinct verb) as unique_verbs
        CYPHER
        
        result = session.run(stats_query)
        stats = result.single
        
        if stats
          summary << "📊 #{stats['total_relationships']} total relationships using #{stats['unique_verbs']} unique verbs"
        end
      end
      
      summary.join("\n")
    end
  end
end