# frozen_string_literal: true

module Graph
  # Verifies the integrity of the graph after assembly
  class IntegrityVerifier
    def initialize(transaction)
      @tx = transaction
      @errors = []
      @warnings = []
    end
    
    def verify_all
      Rails.logger.info "Verifying graph integrity"
      
      # Run all verification checks
      verify_required_properties
      verify_rights_pointers
      verify_time_fields
      verify_relationship_constraints
      verify_reverse_edges
      verify_canonical_names
      
      valid = @errors.empty?
      
      {
        valid: valid,
        errors: @errors,
        warnings: @warnings,
        summary: build_summary
      }
    end
    
    private
    
    def verify_required_properties
      # Check that all nodes have required properties
      
      # All nodes must have an id
      query = <<~CYPHER
        MATCH (n)
        WHERE n.id IS NULL
        RETURN labels(n)[0] as label, count(n) as count
      CYPHER
      
      result = @tx.run(query)
      result.each do |record|
        @errors << "#{record[:count]} #{record[:label]} nodes missing id property"
      end
      
      # Nodes requiring repr_text
      %w[Idea Manifest Experience Practical Emanation].each do |label|
        check_query = <<~CYPHER
          MATCH (n:#{label})
          WHERE n.repr_text IS NULL OR n.repr_text = ''
          RETURN count(n) as count
        CYPHER
        
        result = @tx.run(check_query).single
        if result[:count] > 0
          @errors << "#{result[:count]} #{label} nodes missing repr_text"
        end
      end
    end
    
    def verify_rights_pointers
      # Check that all content nodes have rights pointers
      content_labels = %w[Idea Manifest Experience Practical Emanation Relational Evolutionary]
      
      content_labels.each do |label|
        query = <<~CYPHER
          MATCH (n:#{label})
          WHERE n.rights_id IS NULL
          RETURN count(n) as count
        CYPHER
        
        result = @tx.run(query).single
        if result[:count] > 0
          @errors << "#{result[:count]} #{label} nodes missing rights_id"
        end
        
        # Also check for actual HAS_RIGHTS relationship
        rel_query = <<~CYPHER
          MATCH (n:#{label})
          WHERE NOT (n)-[:HAS_RIGHTS]->(:ProvenanceAndRights)
          RETURN count(n) as count
        CYPHER
        
        result = @tx.run(rel_query).single
        if result[:count] > 0
          @warnings << "#{result[:count]} #{label} nodes missing HAS_RIGHTS relationship"
        end
      end
    end
    
    def verify_time_fields
      # Verify that nodes have appropriate time fields
      
      # Nodes with valid_time_start
      valid_time_labels = %w[Idea Manifest Practical Emanation Relational Evolutionary ProvenanceAndRights Lexicon]
      
      valid_time_labels.each do |label|
        query = <<~CYPHER
          MATCH (n:#{label})
          WHERE n.valid_time_start IS NULL
          RETURN count(n) as count
        CYPHER
        
        result = @tx.run(query).single
        if result[:count] > 0
          @warnings << "#{result[:count]} #{label} nodes missing valid_time_start"
        end
      end
      
      # Nodes with observed_at
      observed_at_labels = %w[Experience Intent]
      
      observed_at_labels.each do |label|
        query = <<~CYPHER
          MATCH (n:#{label})
          WHERE n.observed_at IS NULL
          RETURN count(n) as count
        CYPHER
        
        result = @tx.run(query).single
        if result[:count] > 0
          @warnings << "#{result[:count]} #{label} nodes missing observed_at"
        end
      end
    end
    
    def verify_relationship_constraints
      # Verify that relationships follow the verb glossary rules
      
      # Check for invalid relationship types
      valid_verbs = Graph::EdgeLoader::VERB_GLOSSARY.keys.map(&:upcase)
      valid_verbs << 'HAS_RIGHTS' # Special relationship for rights
      
      query = <<~CYPHER
        MATCH ()-[r]->()
        WITH type(r) as rel_type, count(r) as count
        WHERE NOT rel_type IN $valid_verbs
        RETURN rel_type, count
      CYPHER
      
      result = @tx.run(query, valid_verbs: valid_verbs)
      result.each do |record|
        @warnings << "Found #{record[:count]} relationships of unknown type: #{record[:rel_type]}"
      end
      
      # Verify source/target constraints for specific verbs
      Graph::EdgeLoader::VERB_GLOSSARY.each do |verb, config|
        next if config[:source] == '*' || config[:target] == '*'
        
        source_labels = Array(config[:source])
        target_labels = Array(config[:target])
        
        source_labels.each do |source_label|
          target_labels.each do |target_label|
            verify_relationship_endpoints(verb.upcase, source_label, target_label)
          end
        end
      end
    end
    
    def verify_relationship_endpoints(verb, expected_source, expected_target)
      # Check that relationships have correct source and target types
      query = <<~CYPHER
        MATCH (source)-[r:#{verb}]->(target)
        WHERE NOT '#{expected_source}' IN labels(source)
           OR NOT '#{expected_target}' IN labels(target)
        RETURN count(r) as count
      CYPHER
      
      result = @tx.run(query).single
      if result[:count] > 0
        @warnings << "#{result[:count]} #{verb} relationships with incorrect endpoints (expected #{expected_source}->#{expected_target})"
      end
    end
    
    def verify_reverse_edges
      # Verify that reverse edges exist where required
      Graph::EdgeLoader::VERB_GLOSSARY.each do |verb, config|
        next unless config[:reverse]
        
        forward_verb = verb.upcase
        reverse_verb = config[:reverse].upcase
        
        # Count forward edges
        forward_query = <<~CYPHER
          MATCH ()-[r:#{forward_verb}]->()
          RETURN count(r) as count
        CYPHER
        
        forward_count = @tx.run(forward_query).single[:count]
        
        # Count reverse edges
        reverse_query = <<~CYPHER
          MATCH ()-[r:#{reverse_verb}]->()
          RETURN count(r) as count
        CYPHER
        
        reverse_count = @tx.run(reverse_query).single[:count]
        
        if forward_count != reverse_count && !config[:symmetric]
          @warnings << "Mismatch in #{verb}/#{config[:reverse]} edges: #{forward_count} forward, #{reverse_count} reverse"
        end
      end
    end
    
    def verify_canonical_names
      # Verify that Ideas use canonical names
      query = <<~CYPHER
        MATCH (i:Idea)
        WHERE i.label IS NULL OR i.label = ''
        RETURN count(i) as count
      CYPHER
      
      result = @tx.run(query).single
      if result[:count] > 0
        @errors << "#{result[:count]} Idea nodes missing canonical label"
      end
      
      # Check that paths can be textized
      sample_path_query = <<~CYPHER
        MATCH path = (i:Idea)-[:EMBODIES]->(m:Manifest)-[:ELICITS]->(e:Experience)
        RETURN i.label as idea_label, m.label as manifest_label, 
               e.agent_label as experience_agent
        LIMIT 5
      CYPHER
      
      result = @tx.run(sample_path_query)
      result.each do |record|
        if record[:idea_label].nil? || record[:manifest_label].nil?
          @warnings << "Path missing labels for textization: #{record.inspect}"
        end
      end
    end
    
    def build_summary
      {
        total_nodes: count_nodes,
        total_edges: count_edges,
        nodes_by_type: count_nodes_by_type,
        edges_by_type: count_edges_by_type,
        error_count: @errors.length,
        warning_count: @warnings.length
      }
    end
    
    def count_nodes
      query = "MATCH (n) RETURN count(n) as count"
      @tx.run(query).single[:count]
    end
    
    def count_edges
      query = "MATCH ()-[r]->() RETURN count(r) as count"
      @tx.run(query).single[:count]
    end
    
    def count_nodes_by_type
      query = <<~CYPHER
        MATCH (n)
        RETURN labels(n)[0] as label, count(n) as count
        ORDER BY count DESC
      CYPHER
      
      result = {}
      @tx.run(query).each do |record|
        result[record[:label]] = record[:count]
      end
      result
    end
    
    def count_edges_by_type
      query = <<~CYPHER
        MATCH ()-[r]->()
        RETURN type(r) as type, count(r) as count
        ORDER BY count DESC
      CYPHER
      
      result = {}
      @tx.run(query).each do |record|
        result[record[:type]] = record[:count]
      end
      result
    end
  end
end