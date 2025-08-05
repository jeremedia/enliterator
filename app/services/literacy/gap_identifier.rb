# frozen_string_literal: true

module Literacy
  class GapIdentifier
    attr_reader :batch_id
    
    PRIORITY_WEIGHTS = {
      orphaned_entities: 0.3,
      missing_canonicals: 0.25,
      ambiguous_rights: 0.2,
      sparse_relationships: 0.15,
      temporal_gaps: 0.1
    }.freeze
    
    def initialize(batch_id)
      @batch_id = batch_id
      @neo4j = Graph::Connection.instance
    end
    
    def identify_all_gaps
      gaps = {
        orphaned_entities: find_orphaned_entities,
        missing_canonicals: find_missing_canonicals,
        ambiguous_rights: find_ambiguous_rights,
        sparse_relationships: find_sparse_relationships,
        temporal_gaps: find_temporal_gaps,
        missing_embeddings: find_missing_embeddings
      }
      
      gaps[:summary] = summarize_gaps(gaps)
      gaps[:prioritized_actions] = prioritize_gaps(gaps)
      
      gaps
    end
    
    def find_orphaned_entities
      result = @neo4j.read_transaction do |tx|
        query = <<~CYPHER
          MATCH (n)
          WHERE n.batch_id = $batch_id AND NOT (n)--()
          RETURN labels(n)[0] as pool,
                 n.id as entity_id,
                 n.canonical_name as name,
                 n.repr_text as repr_text
          ORDER BY pool, entity_id
          LIMIT 100
        CYPHER
        
        tx.run(query, batch_id: batch_id)
      end
      
      orphans = []
      by_pool = {}
      
      result.each do |record|
        orphan = {
          entity_id: record[:entity_id],
          pool: record[:pool],
          name: record[:name] || record[:repr_text] || "Entity #{record[:entity_id]}"
        }
        orphans << orphan
        
        by_pool[record[:pool]] ||= []
        by_pool[record[:pool]] << orphan
      end
      
      {
        total_count: count_orphans,
        sample: orphans.first(10),
        by_pool: by_pool.transform_values(&:count),
        severity: calculate_severity(orphans.count, :orphaned)
      }
    end
    
    def find_missing_canonicals
      pools = [Idea, Manifest, Experience, Practical, Emanation, Evolutionary, Relational]
      missing = []
      
      pools.each do |pool_class|
        records = pool_class.where(batch_id: @batch_id)
                           .where(canonical_name: [nil, ''])
                           .limit(20)
        
        records.each do |record|
          missing << {
            entity_id: record.id,
            pool: pool_class.name,
            has_repr_text: record.repr_text.present?,
            has_label: record.respond_to?(:label) && record.label.present?
          }
        end
      end
      
      missing_in_graph = @neo4j.read_transaction do |tx|
        query = <<~CYPHER
          MATCH (n)
          WHERE n.batch_id = $batch_id AND 
                (n.canonical_name IS NULL OR n.canonical_name = '')
          RETURN count(n) as count
        CYPHER
        
        tx.run(query, batch_id: @batch_id).single[:count]
      end
      
      {
        total_count: missing_in_graph || missing.count,
        sample: missing.first(10),
        by_pool: missing.group_by { |m| m[:pool] }.transform_values(&:count),
        severity: calculate_severity(missing_in_graph || 0, :canonical)
      }
    end
    
    def find_ambiguous_rights
      ambiguous = ProvenanceAndRights.where(
        batch_id: @batch_id,
        confidence_level: ['low', 'uncertain', nil]
      ).or(
        ProvenanceAndRights.where(
          batch_id: @batch_id,
          license_type: ['unknown', 'unclear', nil]
        )
      )
      
      sample = ambiguous.limit(10).map do |rights|
        {
          entity_id: rights.entity_id,
          entity_type: rights.entity_type,
          issue: determine_rights_issue(rights),
          publishable: rights.publishable,
          training_eligible: rights.training_eligible
        }
      end
      
      {
        total_count: ambiguous.count,
        sample: sample,
        unverified_count: ProvenanceAndRights.where(
          batch_id: @batch_id,
          verification_status: ['unverified', nil]
        ).count,
        low_confidence_count: ProvenanceAndRights.where(
          batch_id: @batch_id,
          confidence_level: ['low', 'uncertain']
        ).count,
        severity: calculate_severity(ambiguous.count, :rights)
      }
    end
    
    def find_sparse_relationships
      result = @neo4j.read_transaction do |tx|
        query = <<~CYPHER
          MATCH (n)
          WHERE n.batch_id = $batch_id
          WITH n, size((n)--()) as degree
          WHERE degree > 0 AND degree < 2
          RETURN labels(n)[0] as pool,
                 n.id as entity_id,
                 n.canonical_name as name,
                 degree
          ORDER BY degree ASC, pool
          LIMIT 50
        CYPHER
        
        tx.run(query, batch_id: @batch_id)
      end
      
      sparse_nodes = []
      by_pool = {}
      
      result.each do |record|
        node = {
          entity_id: record[:entity_id],
          pool: record[:pool],
          name: record[:name] || "Entity #{record[:entity_id]}",
          relationship_count: record[:degree]
        }
        sparse_nodes << node
        
        by_pool[record[:pool]] ||= []
        by_pool[record[:pool]] << node
      end
      
      sparse_areas = identify_sparse_areas
      
      {
        total_count: count_sparse_nodes,
        sample: sparse_nodes.first(10),
        by_pool: by_pool.transform_values(&:count),
        sparse_areas: sparse_areas,
        severity: calculate_severity(sparse_nodes.count, :sparse)
      }
    end
    
    def find_temporal_gaps
      year_coverage = @neo4j.read_transaction do |tx|
        query = <<~CYPHER
          MATCH (n)
          WHERE n.batch_id = $batch_id AND n.year IS NOT NULL
          RETURN DISTINCT n.year as year
          ORDER BY year
        CYPHER
        
        years = tx.run(query, batch_id: @batch_id).map { |r| r[:year] }
        
        if years.any?
          min_year = years.min
          max_year = years.max
          all_years = (min_year..max_year).to_a
          missing_years = all_years - years
          
          {
            covered_years: years,
            missing_years: missing_years,
            year_range: [min_year, max_year],
            coverage_percentage: (years.count.to_f / all_years.count * 100).round(2)
          }
        else
          { covered_years: [], missing_years: [], year_range: [], coverage_percentage: 0.0 }
        end
      end
      
      entities_without_time = @neo4j.read_transaction do |tx|
        query = <<~CYPHER
          MATCH (n)
          WHERE n.batch_id = $batch_id AND 
                n.time IS NULL AND n.timestamp IS NULL AND 
                n.date IS NULL AND n.year IS NULL
          RETURN count(n) as count, labels(n)[0] as pool
          ORDER BY count DESC
        CYPHER
        
        tx.run(query, batch_id: @batch_id).map do |r|
          { pool: r[:pool], count: r[:count] }
        end
      end
      
      {
        year_coverage: year_coverage,
        entities_without_temporal_data: entities_without_time,
        total_without_time: entities_without_time.sum { |e| e[:count] },
        severity: calculate_severity(year_coverage[:missing_years]&.count || 0, :temporal)
      }
    end
    
    def find_missing_embeddings
      embedded_count = Embedding.where(batch_id: @batch_id).count
      
      eligible_count = @neo4j.read_transaction do |tx|
        query = <<~CYPHER
          MATCH (n)-[:HAS_RIGHTS]->(r:Rights)
          WHERE n.batch_id = $batch_id AND r.training_eligible = true
          RETURN count(n) as count
        CYPHER
        
        tx.run(query, batch_id: @batch_id).single[:count]
      end || 0
      
      missing = eligible_count - embedded_count
      
      {
        eligible_entities: eligible_count,
        embedded_entities: embedded_count,
        missing_embeddings: [missing, 0].max,
        coverage_percentage: eligible_count > 0 ? (embedded_count.to_f / eligible_count * 100).round(2) : 0.0,
        severity: calculate_severity(missing, :embeddings)
      }
    end
    
    def prioritize_gaps(gaps)
      priorities = []
      
      gaps.each do |gap_type, gap_data|
        next if [:summary, :prioritized_actions].include?(gap_type)
        
        severity = gap_data[:severity] || :low
        weight = PRIORITY_WEIGHTS[gap_type] || 0.05
        
        score = calculate_priority_score(severity, weight)
        
        priorities << {
          gap_type: gap_type,
          severity: severity,
          score: score,
          action: recommend_action(gap_type, gap_data),
          estimated_effort: estimate_effort(gap_type, gap_data)
        }
      end
      
      priorities.sort_by { |p| -p[:score] }
    end
    
    private
    
    def count_orphans
      @neo4j.read_transaction do |tx|
        query = <<~CYPHER
          MATCH (n)
          WHERE n.batch_id = $batch_id AND NOT (n)--()
          RETURN count(n) as count
        CYPHER
        
        tx.run(query, batch_id: @batch_id).single[:count]
      end || 0
    end
    
    def count_sparse_nodes
      @neo4j.read_transaction do |tx|
        query = <<~CYPHER
          MATCH (n)
          WHERE n.batch_id = $batch_id
          WITH n, size((n)--()) as degree
          WHERE degree > 0 AND degree < 2
          RETURN count(n) as count
        CYPHER
        
        tx.run(query, batch_id: @batch_id).single[:count]
      end || 0
    end
    
    def identify_sparse_areas
      @neo4j.read_transaction do |tx|
        query = <<~CYPHER
          MATCH (n)-[r]-(m)
          WHERE n.batch_id = $batch_id AND m.batch_id = $batch_id
          WITH type(r) as relationship_type, count(*) as count
          WHERE count < 5
          RETURN relationship_type, count
          ORDER BY count ASC
          LIMIT 10
        CYPHER
        
        tx.run(query, batch_id: @batch_id).map do |record|
          {
            relationship_type: record[:relationship_type],
            count: record[:count]
          }
        end
      end
    end
    
    def determine_rights_issue(rights)
      issues = []
      issues << 'low_confidence' if ['low', 'uncertain'].include?(rights.confidence_level)
      issues << 'unknown_license' if ['unknown', 'unclear'].include?(rights.license_type)
      issues << 'unverified' if ['unverified', nil].include?(rights.verification_status)
      issues << 'missing_source' if rights.source_url.blank?
      
      issues.join(', ')
    end
    
    def calculate_severity(count, gap_type)
      thresholds = case gap_type
      when :orphaned
        { critical: 100, high: 50, medium: 20, low: 5 }
      when :canonical
        { critical: 100, high: 50, medium: 20, low: 5 }
      when :rights
        { critical: 50, high: 25, medium: 10, low: 3 }
      when :sparse
        { critical: 200, high: 100, medium: 50, low: 20 }
      when :temporal
        { critical: 10, high: 5, medium: 3, low: 1 }
      when :embeddings
        { critical: 500, high: 200, medium: 50, low: 10 }
      else
        { critical: 100, high: 50, medium: 20, low: 5 }
      end
      
      return :critical if count >= thresholds[:critical]
      return :high if count >= thresholds[:high]
      return :medium if count >= thresholds[:medium]
      return :low if count >= thresholds[:low]
      :minimal
    end
    
    def calculate_priority_score(severity, weight)
      severity_scores = {
        critical: 1.0,
        high: 0.75,
        medium: 0.5,
        low: 0.25,
        minimal: 0.1
      }
      
      (severity_scores[severity] || 0.1) * weight * 100
    end
    
    def recommend_action(gap_type, gap_data)
      case gap_type
      when :orphaned_entities
        "Connect #{gap_data[:total_count]} orphaned entities to the graph through relationship extraction"
      when :missing_canonicals
        "Generate canonical names for #{gap_data[:total_count]} entities using lexicon service"
      when :ambiguous_rights
        "Clarify rights for #{gap_data[:total_count]} entities through manual review or inference"
      when :sparse_relationships
        "Enrich #{gap_data[:total_count]} sparsely connected nodes with additional relationships"
      when :temporal_gaps
        "Add temporal data for #{gap_data[:total_without_time]} entities"
      when :missing_embeddings
        "Generate embeddings for #{gap_data[:missing_embeddings]} eligible entities"
      else
        "Review and address #{gap_type.to_s.humanize.downcase}"
      end
    end
    
    def estimate_effort(gap_type, gap_data)
      count = case gap_type
      when :orphaned_entities then gap_data[:total_count]
      when :missing_canonicals then gap_data[:total_count]
      when :ambiguous_rights then gap_data[:total_count]
      when :sparse_relationships then gap_data[:total_count]
      when :temporal_gaps then gap_data[:total_without_time]
      when :missing_embeddings then gap_data[:missing_embeddings]
      else 0
      end
      
      return 'minimal' if count < 10
      return 'low' if count < 50
      return 'medium' if count < 200
      return 'high' if count < 1000
      'very_high'
    end
    
    def summarize_gaps(gaps)
      total_issues = 0
      critical_count = 0
      high_count = 0
      
      gaps.each do |gap_type, gap_data|
        next if [:summary, :prioritized_actions].include?(gap_type)
        
        count = gap_data[:total_count] || 0
        total_issues += count
        
        severity = gap_data[:severity]
        critical_count += 1 if severity == :critical
        high_count += 1 if severity == :high
      end
      
      {
        total_issues: total_issues,
        critical_gaps: critical_count,
        high_priority_gaps: high_count,
        gap_types_identified: gaps.keys.count - 2,
        overall_severity: determine_overall_severity(critical_count, high_count)
      }
    end
    
    def determine_overall_severity(critical_count, high_count)
      return :critical if critical_count > 0
      return :high if high_count > 1
      return :medium if high_count == 1
      :low
    end
  end
end