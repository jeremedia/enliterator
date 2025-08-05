# frozen_string_literal: true

module Literacy
  class EnliteracyScorer
    WEIGHT_DISTRIBUTION = {
      coverage: 0.40,
      relationships: 0.30,
      rights: 0.20,
      retrieval: 0.10
    }.freeze
    
    MINIMUM_PASSING_SCORE = 70.0
    
    attr_reader :batch_id
    
    def initialize(batch_id)
      @batch_id = batch_id
    end
    
    def calculate_score
      metrics = gather_all_metrics
      
      component_scores = calculate_component_scores(metrics)
      weighted_score = calculate_weighted_score(component_scores)
      
      {
        batch_id: @batch_id,
        enliteracy_score: weighted_score.round(2),
        passes_threshold: weighted_score >= MINIMUM_PASSING_SCORE,
        minimum_required: MINIMUM_PASSING_SCORE,
        component_scores: component_scores,
        weights: WEIGHT_DISTRIBUTION,
        metrics: metrics,
        recommendations: generate_recommendations(component_scores, weighted_score),
        timestamp: Time.current.iso8601
      }
    end
    
    def generate_report
      score_data = calculate_score
      maturity_data = Literacy::MaturityAssessor.new(@batch_id).assess_batch
      gap_data = Literacy::GapIdentifier.new(@batch_id).identify_all_gaps
      
      {
        executive_summary: generate_executive_summary(score_data, maturity_data),
        enliteracy_score: score_data,
        maturity_assessment: maturity_data,
        gap_analysis: gap_data,
        readiness_assessment: assess_readiness(score_data, maturity_data, gap_data),
        next_steps: determine_next_steps(score_data, maturity_data, gap_data),
        generated_at: Time.current.iso8601
      }
    end
    
    private
    
    def gather_all_metrics
      coverage_analyzer = Literacy::CoverageAnalyzer.new(@batch_id)
      coverage_metrics = coverage_analyzer.analyze_all
      
      rights_metrics = gather_rights_metrics
      retrieval_metrics = gather_retrieval_metrics
      
      {
        coverage: coverage_metrics,
        rights: rights_metrics,
        retrieval: retrieval_metrics
      }
    end
    
    def gather_rights_metrics
      total_entities = count_total_entities
      
      rights_assigned = ProvenanceAndRights.where(batch_id: @batch_id).count
      publishable = ProvenanceAndRights.where(batch_id: @batch_id, publishable: true).count
      training_eligible = ProvenanceAndRights.where(batch_id: @batch_id, training_eligible: true).count
      verified = ProvenanceAndRights.where(batch_id: @batch_id, verification_status: 'verified').count
      
      {
        total_entities: total_entities,
        rights_assigned: rights_assigned,
        rights_coverage_percentage: calculate_percentage(rights_assigned, total_entities),
        publishable_count: publishable,
        publishable_percentage: calculate_percentage(publishable, rights_assigned),
        training_eligible_count: training_eligible,
        training_eligible_percentage: calculate_percentage(training_eligible, rights_assigned),
        verified_count: verified,
        verification_percentage: calculate_percentage(verified, rights_assigned)
      }
    end
    
    def gather_retrieval_metrics
      embeddings_count = Embedding.where(batch_id: @batch_id).count
      eligible_for_embedding = count_training_eligible_entities
      
      embedding_coverage = calculate_percentage(embeddings_count, eligible_for_embedding)
      
      retrieval_quality = if embeddings_count > 0
        sample_retrieval_quality
      else
        0.0
      end
      
      {
        embeddings_count: embeddings_count,
        eligible_entities: eligible_for_embedding,
        embedding_coverage_percentage: embedding_coverage,
        retrieval_quality_score: retrieval_quality,
        index_health: check_index_health
      }
    end
    
    def calculate_component_scores(metrics)
      {
        coverage: calculate_coverage_score(metrics[:coverage]),
        relationships: calculate_relationships_score(metrics[:coverage]),
        rights: calculate_rights_score(metrics[:rights]),
        retrieval: calculate_retrieval_score(metrics[:retrieval])
      }
    end
    
    def calculate_coverage_score(coverage_metrics)
      subscores = {
        idea_coverage: normalize_percentage(coverage_metrics[:idea_coverage][:coverage_percentage]),
        temporal_coverage: normalize_percentage(coverage_metrics[:temporal_coverage][:temporal_coverage_percentage]),
        spatial_coverage: normalize_percentage(coverage_metrics[:spatial_coverage][:spatial_coverage_percentage]),
        path_completeness: normalize_percentage(coverage_metrics[:path_completeness][:path_coverage_percentage])
      }
      
      weights = {
        idea_coverage: 0.35,
        temporal_coverage: 0.25,
        spatial_coverage: 0.20,
        path_completeness: 0.20
      }
      
      weighted_average(subscores, weights)
    end
    
    def calculate_relationships_score(coverage_metrics)
      density = coverage_metrics[:relationship_density][:average_edges_per_node] || 0
      orphan_percentage = coverage_metrics[:relationship_density][:orphan_percentage] || 100
      distribution_balance = coverage_metrics[:pool_distribution][:balance_score] || 0
      
      density_score = case density
      when 0...0.5 then 0
      when 0.5...1.0 then 20
      when 1.0...2.0 then 40
      when 2.0...3.0 then 60
      when 3.0...4.0 then 80
      else 100
      end
      
      orphan_penalty = [100 - orphan_percentage, 0].max
      
      subscores = {
        density: density_score,
        connectivity: orphan_penalty,
        distribution: distribution_balance
      }
      
      weights = {
        density: 0.40,
        connectivity: 0.35,
        distribution: 0.25
      }
      
      weighted_average(subscores, weights)
    end
    
    def calculate_rights_score(rights_metrics)
      subscores = {
        coverage: normalize_percentage(rights_metrics[:rights_coverage_percentage]),
        publishable: normalize_percentage(rights_metrics[:publishable_percentage]),
        training_eligible: normalize_percentage(rights_metrics[:training_eligible_percentage]),
        verification: normalize_percentage(rights_metrics[:verification_percentage])
      }
      
      weights = {
        coverage: 0.30,
        publishable: 0.25,
        training_eligible: 0.25,
        verification: 0.20
      }
      
      weighted_average(subscores, weights)
    end
    
    def calculate_retrieval_score(retrieval_metrics)
      subscores = {
        embedding_coverage: normalize_percentage(retrieval_metrics[:embedding_coverage_percentage]),
        retrieval_quality: retrieval_metrics[:retrieval_quality_score],
        index_health: retrieval_metrics[:index_health]
      }
      
      weights = {
        embedding_coverage: 0.50,
        retrieval_quality: 0.30,
        index_health: 0.20
      }
      
      weighted_average(subscores, weights)
    end
    
    def calculate_weighted_score(component_scores)
      total = 0.0
      
      WEIGHT_DISTRIBUTION.each do |component, weight|
        score = component_scores[component] || 0
        total += score * weight
      end
      
      total
    end
    
    def weighted_average(scores, weights)
      total = 0.0
      weight_sum = 0.0
      
      scores.each do |key, score|
        weight = weights[key] || 0
        total += score * weight
        weight_sum += weight
      end
      
      return 0.0 if weight_sum == 0
      total / weight_sum
    end
    
    def normalize_percentage(percentage)
      return 0.0 if percentage.nil? || percentage < 0
      return 100.0 if percentage > 100
      percentage
    end
    
    def count_total_entities
      neo4j = Graph::Connection.instance
      neo4j.read_transaction do |tx|
        query = <<~CYPHER
          MATCH (n)
          WHERE n.batch_id = $batch_id
          RETURN count(n) as count
        CYPHER
        
        tx.run(query, batch_id: @batch_id).single[:count]
      end || 0
    rescue StandardError
      0
    end
    
    def count_training_eligible_entities
      neo4j = Graph::Connection.instance
      neo4j.read_transaction do |tx|
        query = <<~CYPHER
          MATCH (n)
          WHERE n.batch_id = $batch_id
          OPTIONAL MATCH (n)-[:HAS_RIGHTS]->(r:Rights)
          WHERE r.training_eligible = true
          WITH n, r
          WHERE r IS NOT NULL
          RETURN count(DISTINCT n) as count
        CYPHER
        
        tx.run(query, batch_id: @batch_id).single[:count]
      end || 0
    rescue StandardError
      ProvenanceAndRights.where(batch_id: @batch_id, training_eligible: true).count
    end
    
    def sample_retrieval_quality
      sample_size = 10
      embeddings = Embedding.where(batch_id: @batch_id).limit(sample_size)
      
      return 0.0 if embeddings.empty?
      
      quality_scores = embeddings.map do |embedding|
        if embedding.embedding_vector.present? && embedding.repr_text.present?
          base_score = 50.0
          base_score += 20.0 if embedding.canonical_text.present?
          base_score += 15.0 if embedding.path_text.present?
          base_score += 15.0 if embedding.metadata&.dig('pool').present?
          base_score
        else
          0.0
        end
      end
      
      quality_scores.sum / quality_scores.size
    end
    
    def check_index_health
      embeddings_exist = Embedding.where(batch_id: @batch_id).exists?
      return 0.0 unless embeddings_exist
      
      begin
        sample = Embedding.where(batch_id: @batch_id).first
        if sample && sample.embedding_vector.present?
          vector_dimension = sample.embedding_vector.size
          expected_dimension = 1536
          
          dimension_match = vector_dimension == expected_dimension ? 50.0 : 25.0
          
          has_metadata = sample.metadata.present? ? 25.0 : 0.0
          has_texts = sample.repr_text.present? ? 25.0 : 0.0
          
          dimension_match + has_metadata + has_texts
        else
          25.0
        end
      rescue StandardError
        0.0
      end
    end
    
    def calculate_percentage(numerator, denominator)
      return 0.0 if denominator.nil? || denominator == 0
      (numerator.to_f / denominator.to_f * 100).round(2)
    end
    
    def generate_recommendations(component_scores, overall_score)
      recommendations = []
      
      component_scores.each do |component, score|
        if score < 70
          recommendations << generate_component_recommendation(component, score)
        end
      end
      
      if overall_score < MINIMUM_PASSING_SCORE
        gap_to_passing = (MINIMUM_PASSING_SCORE - overall_score).round(2)
        recommendations.unshift({
          priority: 'CRITICAL',
          message: "Score is #{gap_to_passing} points below the minimum threshold of #{MINIMUM_PASSING_SCORE}",
          component: 'overall'
        })
      end
      
      recommendations.sort_by { |r| priority_order(r[:priority]) }
    end
    
    def generate_component_recommendation(component, score)
      priority = case score
      when 0...30 then 'CRITICAL'
      when 30...50 then 'HIGH'
      when 50...70 then 'MEDIUM'
      else 'LOW'
      end
      
      message = case component
      when :coverage
        "Improve data coverage by extracting more canonical terms and linking entities to ideas"
      when :relationships
        "Increase relationship density by connecting orphaned entities and enriching sparse nodes"
      when :rights
        "Enhance rights management by verifying licenses and clarifying ambiguous permissions"
      when :retrieval
        "Improve retrieval capabilities by generating more embeddings and optimizing indices"
      else
        "Review and improve #{component} metrics"
      end
      
      {
        priority: priority,
        component: component,
        current_score: score.round(2),
        target_score: 70.0,
        message: message
      }
    end
    
    def priority_order(priority)
      { 'CRITICAL' => 0, 'HIGH' => 1, 'MEDIUM' => 2, 'LOW' => 3 }[priority] || 4
    end
    
    def generate_executive_summary(score_data, maturity_data)
      status = if score_data[:passes_threshold]
        "READY FOR STAGE 8"
      else
        "REQUIRES IMPROVEMENT"
      end
      
      {
        status: status,
        enliteracy_score: score_data[:enliteracy_score],
        maturity_level: maturity_data[:maturity_level],
        passes_threshold: score_data[:passes_threshold],
        key_strengths: identify_strengths(score_data[:component_scores]),
        key_weaknesses: identify_weaknesses(score_data[:component_scores]),
        critical_gaps: score_data[:recommendations].select { |r| r[:priority] == 'CRITICAL' }.size
      }
    end
    
    def identify_strengths(component_scores)
      component_scores.select { |_, score| score >= 70 }
                     .map { |component, score| "#{component.to_s.capitalize}: #{score.round(1)}%" }
    end
    
    def identify_weaknesses(component_scores)
      component_scores.select { |_, score| score < 70 }
                     .map { |component, score| "#{component.to_s.capitalize}: #{score.round(1)}%" }
    end
    
    def assess_readiness(score_data, maturity_data, gap_data)
      {
        stage_8_ready: score_data[:passes_threshold] && maturity_data[:maturity_level] >= 'M5',
        blocking_issues: identify_blocking_issues(score_data, maturity_data, gap_data),
        estimated_effort_to_ready: estimate_readiness_effort(score_data, gap_data)
      }
    end
    
    def identify_blocking_issues(score_data, maturity_data, gap_data)
      issues = []
      
      unless score_data[:passes_threshold]
        issues << "Enliteracy score below threshold (#{score_data[:enliteracy_score]} < #{MINIMUM_PASSING_SCORE})"
      end
      
      if maturity_data[:maturity_level] < 'M5'
        issues << "Maturity level too low (#{maturity_data[:maturity_level]} < M5)"
      end
      
      if gap_data[:summary][:critical_gaps] > 0
        issues << "#{gap_data[:summary][:critical_gaps]} critical gaps identified"
      end
      
      issues
    end
    
    def estimate_readiness_effort(score_data, gap_data)
      return 'none' if score_data[:passes_threshold]
      
      gap = MINIMUM_PASSING_SCORE - score_data[:enliteracy_score]
      critical_gaps = gap_data[:summary][:critical_gaps] || 0
      
      return 'very_high' if gap > 30 || critical_gaps > 3
      return 'high' if gap > 20 || critical_gaps > 1
      return 'medium' if gap > 10
      return 'low' if gap > 5
      'minimal'
    end
    
    def determine_next_steps(score_data, maturity_data, gap_data)
      steps = []
      
      if score_data[:passes_threshold]
        steps << {
          action: "Proceed to Stage 8: Autogenerated Deliverables",
          priority: 'immediate',
          description: "Generate prompt packs, evaluation bundles, and refresh cadence"
        }
      else
        gap_data[:prioritized_actions]&.first(3)&.each do |action|
          steps << {
            action: action[:action],
            priority: action[:severity],
            estimated_effort: action[:estimated_effort]
          }
        end
        
        steps << {
          action: "Re-run literacy scoring after improvements",
          priority: 'required',
          description: "Must achieve score ≥ #{MINIMUM_PASSING_SCORE} to proceed"
        }
      end
      
      steps
    end
  end
end