# frozen_string_literal: true

module Literacy
  class CoverageAnalyzer
    attr_reader :batch_id
    
    def initialize(batch_id)
      @batch_id = batch_id
      @neo4j = Graph::Connection.instance
    end
    
    def analyze_all
      {
        idea_coverage: analyze_idea_coverage,
        relationship_density: analyze_relationship_density,
        path_completeness: analyze_path_completeness,
        temporal_coverage: analyze_temporal_coverage,
        spatial_coverage: analyze_spatial_coverage,
        pool_distribution: analyze_pool_distribution
      }
    end
    
    def analyze_idea_coverage
      result = @neo4j.read_transaction do |tx|
        query = <<~CYPHER
          MATCH (n)
          WHERE n.batch_id = $batch_id AND (n:Manifest OR n:Experience)
          WITH count(n) as total_nodes
          MATCH (n)-[:EMBODIES|IS_EMBODIMENT_OF|ELICITS|IS_ELICITED_BY|INSPIRES|IS_INSPIRED_BY]-(i:Idea)
          WHERE n.batch_id = $batch_id AND i.batch_id = $batch_id 
            AND (n:Manifest OR n:Experience)
          WITH total_nodes, count(DISTINCT n) as connected_nodes
          RETURN total_nodes, connected_nodes,
                 CASE WHEN total_nodes > 0 
                      THEN toFloat(connected_nodes) / toFloat(total_nodes) * 100 
                      ELSE 0.0 END as coverage_percentage
        CYPHER
        
        tx.run(query, batch_id: batch_id).single
      end
      
      {
        total_manifest_experience: result[:total_nodes] || 0,
        connected_to_ideas: result[:connected_nodes] || 0,
        coverage_percentage: result[:coverage_percentage] || 0.0,
        status: coverage_status(result[:coverage_percentage] || 0.0)
      }
    end
    
    def analyze_relationship_density
      result = @neo4j.read_transaction do |tx|
        query = <<~CYPHER
          MATCH (n)
          WHERE n.batch_id = $batch_id
          WITH n, size((n)--()) as degree
          RETURN avg(degree) as avg_density,
                 min(degree) as min_density,
                 max(degree) as max_density,
                 stDev(degree) as std_dev,
                 count(n) as total_nodes,
                 count(CASE WHEN degree = 0 THEN 1 END) as orphan_count
        CYPHER
        
        tx.run(query, batch_id: batch_id).single
      end
      
      {
        average_edges_per_node: result[:avg_density] || 0.0,
        min_edges: result[:min_density] || 0,
        max_edges: result[:max_density] || 0,
        standard_deviation: result[:std_dev] || 0.0,
        total_nodes: result[:total_nodes] || 0,
        orphan_nodes: result[:orphan_count] || 0,
        orphan_percentage: calculate_percentage(result[:orphan_count], result[:total_nodes]),
        status: density_status(result[:avg_density] || 0.0)
      }
    end
    
    def analyze_path_completeness
      result = @neo4j.read_transaction do |tx|
        query = <<~CYPHER
          MATCH (i:Idea)
          WHERE i.batch_id = $batch_id
          WITH i
          OPTIONAL MATCH path = (i)-[*1..3]-(m:Manifest)
          WHERE m.batch_id = $batch_id AND 
                all(node in nodes(path) WHERE node.batch_id = $batch_id)
          WITH i, count(DISTINCT m) as connected_manifests
          RETURN count(i) as total_ideas,
                 count(CASE WHEN connected_manifests > 0 THEN 1 END) as connected_ideas,
                 avg(connected_manifests) as avg_manifests_per_idea
        CYPHER
        
        tx.run(query, batch_id: batch_id).single
      end
      
      connected_percentage = calculate_percentage(result[:connected_ideas], result[:total_ideas])
      
      {
        total_ideas: result[:total_ideas] || 0,
        ideas_with_manifest_paths: result[:connected_ideas] || 0,
        path_coverage_percentage: connected_percentage,
        avg_manifests_per_idea: result[:avg_manifests_per_idea] || 0.0,
        status: path_status(connected_percentage)
      }
    end
    
    def analyze_temporal_coverage
      result = @neo4j.read_transaction do |tx|
        query = <<~CYPHER
          MATCH (n)
          WHERE n.batch_id = $batch_id
          WITH n,
               CASE 
                 WHEN n.time IS NOT NULL THEN 1
                 WHEN n.timestamp IS NOT NULL THEN 1
                 WHEN n.date IS NOT NULL THEN 1
                 WHEN n.year IS NOT NULL THEN 1
                 ELSE 0
               END as has_time
          RETURN count(n) as total_nodes,
                 sum(has_time) as nodes_with_time,
                 labels(n)[0] as pool,
                 count(n) as pool_count,
                 sum(has_time) as pool_with_time
          ORDER BY pool
        CYPHER
        
        tx.run(query, batch_id: batch_id)
      end
      
      totals = { total: 0, with_time: 0 }
      by_pool = {}
      
      result.each do |record|
        if record[:pool]
          by_pool[record[:pool]] = {
            total: record[:pool_count],
            with_time: record[:pool_with_time],
            coverage_percentage: calculate_percentage(record[:pool_with_time], record[:pool_count])
          }
          totals[:total] += record[:pool_count]
          totals[:with_time] += record[:pool_with_time]
        end
      end
      
      overall_percentage = calculate_percentage(totals[:with_time], totals[:total])
      
      {
        total_nodes: totals[:total],
        nodes_with_temporal_data: totals[:with_time],
        temporal_coverage_percentage: overall_percentage,
        by_pool: by_pool,
        status: temporal_status(overall_percentage)
      }
    end
    
    def analyze_spatial_coverage
      result = @neo4j.read_transaction do |tx|
        query = <<~CYPHER
          MATCH (m:Manifest)
          WHERE m.batch_id = $batch_id
          WITH m,
               CASE 
                 WHEN m.location IS NOT NULL THEN 1
                 WHEN m.coordinates IS NOT NULL THEN 1
                 WHEN m.address IS NOT NULL THEN 1
                 WHEN m.placement IS NOT NULL THEN 1
                 WHEN exists((m)-[:LOCATED_AT]-()) THEN 1
                 ELSE 0
               END as has_location
          RETURN count(m) as total_manifests,
                 sum(has_location) as manifests_with_location
        CYPHER
        
        tx.run(query, batch_id: batch_id).single
      end
      
      percentage = calculate_percentage(
        result[:manifests_with_location] || 0,
        result[:total_manifests] || 0
      )
      
      {
        total_manifests: result[:total_manifests] || 0,
        manifests_with_location: result[:manifests_with_location] || 0,
        spatial_coverage_percentage: percentage,
        status: spatial_status(percentage)
      }
    end
    
    def analyze_pool_distribution
      @neo4j.read_transaction do |tx|
        query = <<~CYPHER
          MATCH (n)
          WHERE n.batch_id = $batch_id
          RETURN labels(n)[0] as pool, count(n) as count
          ORDER BY count DESC
        CYPHER
        
        result = tx.run(query, batch_id: batch_id)
        
        distribution = {}
        total = 0
        
        result.each do |record|
          if record[:pool]
            distribution[record[:pool]] = record[:count]
            total += record[:count]
          end
        end
        
        {
          distribution: distribution,
          total_entities: total,
          pool_count: distribution.keys.length,
          balance_score: calculate_distribution_balance(distribution)
        }
      end
    end
    
    private
    
    def calculate_percentage(numerator, denominator)
      return 0.0 if denominator.nil? || denominator == 0
      (numerator.to_f / denominator.to_f * 100).round(2)
    end
    
    def calculate_distribution_balance(distribution)
      return 0.0 if distribution.empty?
      
      values = distribution.values
      avg = values.sum.to_f / values.length
      return 100.0 if avg == 0
      
      variance = values.map { |v| (v - avg) ** 2 }.sum / values.length
      std_dev = Math.sqrt(variance)
      
      coefficient_of_variation = std_dev / avg
      balance = [100 * (1 - coefficient_of_variation), 0].max
      balance.round(2)
    end
    
    def coverage_status(percentage)
      case percentage
      when 80..100 then :excellent
      when 60..79 then :good
      when 40..59 then :moderate
      when 20..39 then :poor
      else :critical
      end
    end
    
    def density_status(avg_density)
      case avg_density
      when 4..Float::INFINITY then :excellent
      when 2.5..3.9 then :good
      when 1.5..2.4 then :moderate
      when 0.5..1.4 then :poor
      else :critical
      end
    end
    
    def path_status(percentage)
      case percentage
      when 75..100 then :excellent
      when 50..74 then :good
      when 25..49 then :moderate
      when 10..24 then :poor
      else :critical
      end
    end
    
    def temporal_status(percentage)
      case percentage
      when 80..100 then :excellent
      when 60..79 then :good
      when 40..59 then :moderate
      when 20..39 then :poor
      else :critical
      end
    end
    
    def spatial_status(percentage)
      case percentage
      when 70..100 then :excellent
      when 50..69 then :good
      when 30..49 then :moderate
      when 10..29 then :poor
      else :critical
      end
    end
  end
end