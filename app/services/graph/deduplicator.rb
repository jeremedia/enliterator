# frozen_string_literal: true

module Graph
  # Resolves duplicate nodes in the graph based on various criteria
  class Deduplicator
    def initialize(transaction)
      @tx = transaction
      @resolved_count = 0
      @merge_details = []
      @apoc_available = apoc_merge_available?
    end
    
    def resolve_all
      Rails.logger.info "Starting duplicate resolution"
      
      # Resolve duplicates for each pool type
      resolve_idea_duplicates
      resolve_manifest_duplicates
      resolve_experience_duplicates
      resolve_lexicon_duplicates
      resolve_spatial_duplicates if spatial_pool_exists?
      
      {
        resolved_count: @resolved_count,
        merge_details: @merge_details
      }
    end
    
    private
    
    def resolve_idea_duplicates
      # Find Ideas with same canonical label
      query = <<~CYPHER
        MATCH (i1:Idea)
        MATCH (i2:Idea)
        WHERE i1.id < i2.id 
          AND i1.label = i2.label
        RETURN i1.id as id1, i2.id as id2, i1.label as label
      CYPHER
      
      result = @tx.run(query)
      
      result.each do |record|
        merge_nodes('Idea', record[:id1], record[:id2], "Same label: #{record[:label]}")
      end
    end
    
    def resolve_manifest_duplicates
      # Find Manifests with same label and type
      query = <<~CYPHER
        MATCH (m1:Manifest)
        MATCH (m2:Manifest)
        WHERE m1.id < m2.id 
          AND m1.label = m2.label
          AND m1.type = m2.type
        RETURN m1.id as id1, m2.id as id2, m1.label as label, m1.type as type
      CYPHER
      
      result = @tx.run(query)
      
      result.each do |record|
        merge_nodes('Manifest', record[:id1], record[:id2], 
                   "Same label and type: #{record[:label]} (#{record[:type]})")
      end
    end
    
    def resolve_experience_duplicates
      # Find Experiences with very similar narrative text and same agent
      query = <<~CYPHER
        MATCH (e1:Experience)
        MATCH (e2:Experience)
        WHERE e1.id < e2.id 
          AND e1.agent_label = e2.agent_label
          AND e1.observed_at = e2.observed_at
          AND substring(e1.narrative_text, 0, 100) = substring(e2.narrative_text, 0, 100)
        RETURN e1.id as id1, e2.id as id2, e1.agent_label as agent
      CYPHER
      
      result = @tx.run(query)
      
      result.each do |record|
        merge_nodes('Experience', record[:id1], record[:id2], 
                   "Same agent and similar text: #{record[:agent]}")
      end
    end
    
    def resolve_lexicon_duplicates
      # Find Lexicon entries with same canonical term
      query = <<~CYPHER
        MATCH (l1:Lexicon)
        MATCH (l2:Lexicon)
        WHERE l1.id < l2.id 
          AND l1.term = l2.term
        RETURN l1.id as id1, l2.id as id2, l1.term as term
      CYPHER
      
      result = @tx.run(query)
      
      result.each do |record|
        merge_lexicon_nodes(record[:id1], record[:id2], record[:term])
      end
    end
    
    def resolve_spatial_duplicates
      # Find Spatial nodes with same location identifiers
      query = <<~CYPHER
        MATCH (s1:Spatial)
        MATCH (s2:Spatial)
        WHERE s1.id < s2.id 
          AND s1.name = s2.name
          AND s1.year = s2.year
        RETURN s1.id as id1, s2.id as id2, s1.name as name, s1.year as year
      CYPHER
      
      result = @tx.run(query)
      
      result.each do |record|
        merge_nodes('Spatial', record[:id1], record[:id2], 
                   "Same location and year: #{record[:name]} (#{record[:year]})")
      end
    end
    
    def merge_nodes(label, keep_id, remove_id, reason)
      Rails.logger.info "Merging #{label} nodes: keeping #{keep_id}, removing #{remove_id} (#{reason})"
      
      transfer_query = if @apoc_available
        <<~CYPHER
          MATCH (keep:#{label} {id: $keep_id})
          MATCH (remove:#{label} {id: $remove_id})
          OPTIONAL MATCH (remove)-[r_out]->(target)
          WITH keep, remove, collect({r: r_out, target: target}) AS outgoing
          UNWIND outgoing AS o
          WITH keep, remove, o.r AS r, o.target AS target
          WHERE r IS NOT NULL
          CALL apoc.merge.relationship(keep, type(r), {}, properties(r), target) YIELD rel
          WITH keep, remove
          OPTIONAL MATCH (source)-[r_in]->(remove)
          WITH keep, remove, collect({r: r_in, source: source}) AS incoming
          UNWIND incoming AS i
          WITH keep, remove, i.r AS r, i.source AS source
          WHERE r IS NOT NULL
          CALL apoc.merge.relationship(source, type(r), {}, properties(r), keep) YIELD rel
          RETURN count(rel) AS relationships_transferred
        CYPHER
      else
        # Fallback: enumerate known relationship types
        rel_types = begin
          types = []
          if defined?(Graph::EdgeLoader::VERB_GLOSSARY)
            glossary = Graph::EdgeLoader::VERB_GLOSSARY
            types += glossary.keys
            types += glossary.values.map { |v| v[:reverse] }.compact
          end
          types += %w[has_rights implements]
          types.map { |t| t.upcase }.uniq
        end

        outgoing_blocks = rel_types.map do |t|
          "FOREACH (_ IN CASE WHEN r IS NOT NULL AND type(r)='#{t}' THEN [1] ELSE [] END |\n            MERGE (keep)-[new_r:#{t}]->(target)\n            SET new_r = properties(r)\n          )"
        end.join("\n")

        incoming_blocks = rel_types.map do |t|
          "FOREACH (_ IN CASE WHEN r IS NOT NULL AND type(r)='#{t}' THEN [1] ELSE [] END |\n            MERGE (source)-[new_r:#{t}]->(keep)\n            SET new_r = properties(r)\n          )"
        end.join("\n")

        <<~CYPHER
          MATCH (keep:#{label} {id: $keep_id})
          MATCH (remove:#{label} {id: $remove_id})
          OPTIONAL MATCH (remove)-[r]->(target)
          #{outgoing_blocks}
          WITH keep, remove
          OPTIONAL MATCH (source)-[r]->(remove)
          #{incoming_blocks}
          RETURN count(*) as relationships_transferred
        CYPHER
      end
      
      # Execute transfer
      @tx.run(transfer_query, keep_id: keep_id, remove_id: remove_id)
      
      # Skip bulk property merging to avoid overwriting unique keys like `id`.
      # If needed, targeted merges of specific non-identity properties can be added per label.
      
      # Delete the duplicate node
      delete_query = <<~CYPHER
        MATCH (remove:#{label} {id: $remove_id})
        DETACH DELETE remove
      CYPHER
      
      @tx.run(delete_query, remove_id: remove_id)
      
      @resolved_count += 1
      @merge_details << {
        label: label,
        kept: keep_id,
        removed: remove_id,
        reason: reason
      }
    end
    
    def merge_lexicon_nodes(keep_id, remove_id, term)
      Rails.logger.info "Merging Lexicon nodes for term: #{term}"
      
      # Combine surface forms and negative surface forms
      combine_query = <<~CYPHER
        MATCH (keep:Lexicon {id: $keep_id})
        MATCH (remove:Lexicon {id: $remove_id})
        SET keep.surface_forms = 
          CASE 
            WHEN keep.surface_forms IS NOT NULL AND remove.surface_forms IS NOT NULL
            THEN keep.surface_forms + remove.surface_forms
            WHEN keep.surface_forms IS NOT NULL
            THEN keep.surface_forms
            WHEN remove.surface_forms IS NOT NULL
            THEN remove.surface_forms
            ELSE []
          END
        SET keep.negative_surface_forms = 
          CASE 
            WHEN keep.negative_surface_forms IS NOT NULL AND remove.negative_surface_forms IS NOT NULL
            THEN keep.negative_surface_forms + remove.negative_surface_forms
            WHEN keep.negative_surface_forms IS NOT NULL
            THEN keep.negative_surface_forms
            WHEN remove.negative_surface_forms IS NOT NULL
            THEN remove.negative_surface_forms
            ELSE []
          END
        RETURN keep.id
      CYPHER
      
      @tx.run(combine_query, keep_id: keep_id, remove_id: remove_id)
      
      # Now merge the nodes normally
      merge_nodes('Lexicon', keep_id, remove_id, "Same term: #{term}")
    end
    
    # No longer needed: dynamic relationship types handled via APOC
    
    def spatial_pool_exists?
      # Check if Spatial nodes exist in the graph
      query = "MATCH (s:Spatial) RETURN count(s) > 0 as exists"
      result = @tx.run(query).single
      result[:exists]
    end

    def apoc_merge_available?
      begin
        res = @tx.run("SHOW PROCEDURES YIELD name WHERE name='apoc.merge.relationship' RETURN count(*) AS c").single
        res && res[:c].to_i > 0
      rescue
        false
      end
    end
  end
end
