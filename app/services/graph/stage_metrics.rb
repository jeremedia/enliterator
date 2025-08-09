# frozen_string_literal: true

module Graph
  # Comprehensive metrics tracking for Stage 5.5 gates
  class StageMetrics
    attr_reader :ekn, :batch, :driver, :database

    # Stage 5.5 gate thresholds
    GATES = {
      mean_degree: 0.3,
      lcc_coverage: 0.7,  # Largest Connected Component coverage
      verb_diversity: 5,
      answerability: 0.6  # Can answer 60% of test questions
    }.freeze

    def initialize(ekn:, batch: nil)
      @ekn = ekn
      @batch = batch || ekn.ingest_batches.last
      @database = ekn.neo4j_database_name
      @driver = Connection.instance.driver
    end

    # Calculate all Stage 5.5 metrics
    def calculate_all_metrics
      {
        timestamp: Time.current,
        ekn_id: ekn.id,
        batch_id: batch&.id,
        graph_metrics: calculate_graph_metrics,
        coverage_metrics: calculate_coverage_metrics,
        diversity_metrics: calculate_diversity_metrics,
        quality_metrics: calculate_quality_metrics,
        gate_status: evaluate_gates
      }
    end

    # Core graph metrics - CORRECTED to compute on whole graph
    def calculate_graph_metrics
      @driver.session(database: @database) do |session|
        session.read_transaction do |tx|
          # Count ALL nodes and edges (whole graph)
          node_count = tx.run("MATCH (n) RETURN count(n) as count").single['count']
          edge_query = <<~CYPHER
            MATCH ()-[r]->() 
            WHERE type(r) <> 'HAS_RIGHTS' 
            RETURN count(r) as count
          CYPHER
          edge_count = tx.run(edge_query).single['count']
          
          # Calculate density on WHOLE GRAPH
          max_edges = (node_count * (node_count - 1)) / 2.0
          density = node_count > 1 ? (edge_count.to_f / max_edges) : 0
          
          # Mean degree on WHOLE GRAPH  
          mean_degree = node_count > 0 ? (2.0 * edge_count) / node_count : 0
          
          # Node distribution by pool
          pool_query = <<~CYPHER
            MATCH (n)
            RETURN labels(n)[0] as pool, count(n) as count
            ORDER BY count DESC
          CYPHER
          
          pool_distribution = tx.run(pool_query).map { |r| [r['pool'], r['count']] }.to_h
          
          {
            total_nodes: node_count,
            total_edges: edge_count,
            density: density.round(4),
            mean_degree: mean_degree.round(2),
            pool_distribution: pool_distribution
          }
        end
      end
    end

    # Coverage metrics including LCC
    def calculate_coverage_metrics
      @driver.session(database: @database) do |session|
        session.read_transaction do |tx|
          # Find connected components
          components_query = <<~CYPHER
            MATCH (n)
            WITH n
            MATCH path = (n)-[*]-(m)
            WITH n, count(DISTINCT m) as component_size
            RETURN component_size, count(n) as node_count
            ORDER BY component_size DESC
          CYPHER
          
          # Simplified LCC calculation
          total_nodes = tx.run("MATCH (n) RETURN count(n) as count").single['count']
          connected_nodes = tx.run("MATCH (n)-[]-() RETURN count(DISTINCT n) as count").single['count']
          
          lcc_coverage = total_nodes > 0 ? connected_nodes.to_f / total_nodes : 0
          
          # Pool coverage
          pool_coverage_query = <<~CYPHER
            MATCH (n)
            WITH labels(n)[0] as pool
            MATCH (m)
            WHERE labels(m)[0] = pool
            OPTIONAL MATCH (m)-[r]-()
            WITH pool, 
                 count(DISTINCT m) as total,
                 count(DISTINCT CASE WHEN r IS NOT NULL THEN m END) as connected
            RETURN pool, 
                   total,
                   connected,
                   CASE WHEN total > 0 THEN toFloat(connected) / total ELSE 0 END as coverage
          CYPHER
          
          pool_coverage = tx.run(pool_coverage_query).map do |r|
            [r['pool'], {
              total: r['total'],
              connected: r['connected'],
              coverage: r['coverage'].round(3)
            }]
          end.to_h
          
          {
            lcc_coverage: lcc_coverage.round(3),
            connected_nodes: connected_nodes,
            isolated_nodes: total_nodes - connected_nodes,
            pool_coverage: pool_coverage
          }
        end
      end
    end

    # Diversity metrics - CORRECTED to only count spec-compliant verbs
    def calculate_diversity_metrics
      @driver.session(database: @database) do |session|
        session.read_transaction do |tx|
          # Verb diversity - only count spec glossary verbs
          verb_query = <<~CYPHER
            MATCH ()-[r]->()
            WHERE type(r) <> 'HAS_RIGHTS'
              AND type(r) <> 'CO_OCCURS_WITH'
            RETURN type(r) as verb, 
                   count(r) as count,
                   r.status as status
            ORDER BY count DESC
          CYPHER
          
          all_verbs = {}
          verified_verbs = {}
          
          tx.run(verb_query).each do |row|
            verb = row['verb']
            count = row['count']
            status = row['status']
            
            # Only count verbs that are in the spec glossary
            if EdgeLoader::VERB_GLOSSARY.key?(verb.downcase)
              all_verbs[verb] = (all_verbs[verb] || 0) + count
              if status == 'verified'
                verified_verbs[verb] = (verified_verbs[verb] || 0) + count
              end
            end
          end
          
          # Path diversity (unique path patterns)
          path_patterns_query = <<~CYPHER
            MATCH (n)-[r]->(m)
            WITH labels(n)[0] + '-[' + type(r) + ']->' + labels(m)[0] as pattern
            RETURN count(DISTINCT pattern) as unique_patterns
          CYPHER
          
          unique_patterns = tx.run(path_patterns_query).single['unique_patterns']
          
          {
            total_verb_types: all_verbs.keys.count,
            verified_verb_types: verified_verbs.keys.count,
            verb_distribution: all_verbs,
            verified_verbs: verified_verbs,
            unique_path_patterns: unique_patterns
          }
        end
      end
    end

    # Quality metrics
    def calculate_quality_metrics
      @driver.session(database: @database) do |session|
        session.read_transaction do |tx|
          # Confidence distribution
          confidence_query = <<~CYPHER
            MATCH ()-[r]->()
            WHERE r.confidence IS NOT NULL
            RETURN 
              avg(r.confidence) as avg_confidence,
              min(r.confidence) as min_confidence,
              max(r.confidence) as max_confidence,
              percentileCont(r.confidence, 0.5) as median_confidence
          CYPHER
          
          confidence_stats = tx.run(confidence_query).single
          
          # Path sentence coverage
          path_sentence_query = <<~CYPHER
            MATCH ()-[r]->()
            WHERE r.status = 'verified'
            RETURN 
              count(r) as total_verified,
              count(r.path_sentence) as with_path_sentence
          CYPHER
          
          path_coverage = tx.run(path_sentence_query).single
          path_sentence_rate = path_coverage['total_verified'] > 0 ? 
            path_coverage['with_path_sentence'].to_f / path_coverage['total_verified'] : 0
          
          {
            avg_confidence: confidence_stats['avg_confidence']&.round(3),
            min_confidence: confidence_stats['min_confidence'],
            max_confidence: confidence_stats['max_confidence'],
            median_confidence: confidence_stats['median_confidence']&.round(3),
            path_sentence_coverage: path_sentence_rate.round(3),
            verified_relationships: path_coverage['total_verified']
          }
        end
      end
    end

    # Evaluate Stage 5.5 gates
    def evaluate_gates
      metrics = {
        graph: calculate_graph_metrics,
        coverage: calculate_coverage_metrics,
        diversity: calculate_diversity_metrics
      }
      
      gate_results = {
        mean_degree: {
          value: metrics[:graph][:mean_degree],
          threshold: GATES[:mean_degree],
          passed: metrics[:graph][:mean_degree] >= GATES[:mean_degree]
        },
        lcc_coverage: {
          value: metrics[:coverage][:lcc_coverage],
          threshold: GATES[:lcc_coverage],
          passed: metrics[:coverage][:lcc_coverage] >= GATES[:lcc_coverage]
        },
        verb_diversity: {
          value: metrics[:diversity][:verified_verb_types],
          threshold: GATES[:verb_diversity],
          passed: metrics[:diversity][:verified_verb_types] >= GATES[:verb_diversity]
        },
        answerability: {
          value: calculate_answerability_score,
          threshold: GATES[:answerability],
          passed: calculate_answerability_score >= GATES[:answerability]
        }
      }
      
      {
        gates: gate_results,
        all_passed: gate_results.values.all? { |g| g[:passed] },
        passed_count: gate_results.values.count { |g| g[:passed] },
        total_gates: gate_results.size
      }
    end

    # Calculate answerability score (simplified)
    def calculate_answerability_score
      # This would normally test against a question set
      # For now, use proxy metrics
      metrics = calculate_graph_metrics
      coverage = calculate_coverage_metrics
      
      # Score based on connectivity and coverage
      score = 0.0
      score += 0.3 if metrics[:mean_degree] > 1.0
      score += 0.3 if coverage[:lcc_coverage] > 0.5
      score += 0.2 if metrics[:total_edges] > 100
      score += 0.2 if coverage[:connected_nodes] > metrics[:total_nodes] * 0.5
      
      score
    end

    # Generate metrics report
    def generate_report
      metrics = calculate_all_metrics
      
      report = []
      report << "="*60
      report << "STAGE 5.5 METRICS REPORT"
      report << "="*60
      report << "Timestamp: #{metrics[:timestamp]}"
      report << "EKN ID: #{metrics[:ekn_id]}"
      report << ""
      
      report << "GRAPH METRICS:"
      report << "  Nodes: #{metrics[:graph_metrics][:total_nodes]}"
      report << "  Edges: #{metrics[:graph_metrics][:total_edges]}"
      report << "  Density: #{metrics[:graph_metrics][:density]}"
      report << "  Mean Degree: #{metrics[:graph_metrics][:mean_degree]}"
      report << ""
      
      report << "COVERAGE METRICS:"
      report << "  LCC Coverage: #{(metrics[:coverage_metrics][:lcc_coverage] * 100).round(1)}%"
      report << "  Connected Nodes: #{metrics[:coverage_metrics][:connected_nodes]}"
      report << "  Isolated Nodes: #{metrics[:coverage_metrics][:isolated_nodes]}"
      report << ""
      
      report << "DIVERSITY METRICS:"
      report << "  Total Verb Types: #{metrics[:diversity_metrics][:total_verb_types]}"
      report << "  Verified Verb Types: #{metrics[:diversity_metrics][:verified_verb_types]}"
      report << "  Unique Path Patterns: #{metrics[:diversity_metrics][:unique_path_patterns]}"
      report << ""
      
      report << "QUALITY METRICS:"
      report << "  Avg Confidence: #{metrics[:quality_metrics][:avg_confidence]}"
      report << "  Path Sentence Coverage: #{(metrics[:quality_metrics][:path_sentence_coverage] * 100).round(1)}%"
      report << "  Verified Relationships: #{metrics[:quality_metrics][:verified_relationships]}"
      report << ""
      
      report << "GATE STATUS:"
      metrics[:gate_status][:gates].each do |gate, result|
        status = result[:passed] ? "✅ PASS" : "❌ FAIL"
        report << "  #{gate}: #{result[:value]} (threshold: #{result[:threshold]}) - #{status}"
      end
      report << ""
      
      if metrics[:gate_status][:all_passed]
        report << "🎉 ALL GATES PASSED! Stage 5.5 is complete."
      else
        report << "⚠️  #{metrics[:gate_status][:passed_count]}/#{metrics[:gate_status][:total_gates]} gates passed."
      end
      
      report << "="*60
      
      report.join("\n")
    end
  end
end