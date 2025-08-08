# frozen_string_literal: true

module Literacy
  class MaturityAssessor
    MATURITY_LEVELS = {
      'M0' => {
        name: 'Raw Intake',
        description: 'Data ingested but not processed',
        requirements: [:has_ingest_batch]
      },
      'M1' => {
        name: 'Rights Assigned',
        description: 'Rights and provenance tracked',
        requirements: [:has_ingest_batch, :has_rights_assigned]
      },
      'M2' => {
        name: 'Lexicon Extracted',
        description: 'Canonical terms and surface forms identified',
        requirements: [:has_ingest_batch, :has_rights_assigned, :has_lexicon]
      },
      'M3' => {
        name: 'Entities Identified',
        description: 'Ten Pool Canon entities extracted',
        requirements: [:has_ingest_batch, :has_rights_assigned, :has_lexicon, :has_entities]
      },
      'M4' => {
        name: 'Graph Assembled',
        description: 'Knowledge graph with relationships built',
        requirements: [:has_ingest_batch, :has_rights_assigned, :has_lexicon, :has_entities, :has_graph]
      },
      'M5' => {
        name: 'Embeddings Complete',
        description: 'Vector embeddings generated for retrieval',
        requirements: [:has_ingest_batch, :has_rights_assigned, :has_lexicon, :has_entities, :has_graph, :has_embeddings]
      },
      'M6' => {
        name: 'Fully Literate',
        description: 'System can answer why/how/what\'s next',
        requirements: [:has_ingest_batch, :has_rights_assigned, :has_lexicon, :has_entities, 
                       :has_graph, :has_embeddings, :has_high_enliteracy_score]
      }
    }.freeze
    
    attr_reader :batch_id
    
    def initialize(batch_id)
      @batch_id = batch_id
      @neo4j = Graph::Connection.instance
    end
    
    def assess_batch
      capabilities = check_capabilities
      level = determine_level(capabilities)
      details = level_details(level, capabilities)
      
      {
        batch_id: @batch_id,
        maturity_level: level,
        level_name: MATURITY_LEVELS[level][:name],
        level_description: MATURITY_LEVELS[level][:description],
        capabilities: capabilities,
        requirements_met: requirements_met(level, capabilities),
        next_level_requirements: next_level_requirements(level, capabilities),
        timestamp: Time.current.iso8601,
        details: details
      }
    end
    
    def determine_level(capabilities)
      return 'M6' if meets_requirements?('M6', capabilities)
      return 'M5' if meets_requirements?('M5', capabilities)
      return 'M4' if meets_requirements?('M4', capabilities)
      return 'M3' if meets_requirements?('M3', capabilities)
      return 'M2' if meets_requirements?('M2', capabilities)
      return 'M1' if meets_requirements?('M1', capabilities)
      'M0'
    end
    
    private
    
    def check_capabilities
      {
        has_ingest_batch: check_ingest_batch,
        has_rights_assigned: check_rights_assigned,
        has_lexicon: check_lexicon,
        has_entities: check_entities,
        has_graph: check_graph,
        has_embeddings: check_embeddings,
        has_high_enliteracy_score: false,
        metrics: gather_metrics
      }
    end
    
    def check_ingest_batch
      IngestBatch.exists?(id: @batch_id)
    end
    
    def check_rights_assigned
      batch = IngestBatch.find_by(id: @batch_id)
      return false unless batch
      
      count = ProvenanceAndRights.where(batch_id: @batch_id).count
      count > 0 && batch.ingest_items.exists?(rights_status: ['verified', 'inferred'])
    end
    
    def check_lexicon
      Lexicon::CanonicalTerm.where(batch_id: @batch_id).exists?
    end
    
    def check_entities
      pools = [Idea, Manifest, Experience, Practical, Emanation, Evolutionary, Relational]
      
      pools.any? do |pool_class|
        pool_class.where(batch_id: @batch_id).exists?
      end
    end
    
    def check_graph
      @neo4j.read_transaction do |tx|
        query = <<~CYPHER
          MATCH (n)
          WHERE n.batch_id = $batch_id
          RETURN count(n) as node_count
          LIMIT 1
        CYPHER
        
        result = tx.run(query, batch_id: @batch_id).single
        result && result[:node_count] > 0
      end
    rescue StandardError
      false
    end
    
    def check_embeddings
      Embedding.where(batch_id: @batch_id).exists?
    end
    
    def gather_metrics
      metrics = {}
      
      if check_ingest_batch
        batch = IngestBatch.find_by(id: @batch_id)
        metrics[:ingest_items_count] = batch.ingest_items.count
        metrics[:batch_status] = batch.status
      end
      
      if check_rights_assigned
        metrics[:rights_count] = ProvenanceAndRights.where(batch_id: @batch_id).count
        metrics[:publishable_count] = ProvenanceAndRights.where(
          batch_id: @batch_id,
          publishable: true
        ).count
        metrics[:training_eligible_count] = ProvenanceAndRights.where(
          batch_id: @batch_id,
          training_eligible: true
        ).count
      end
      
      if check_lexicon
        metrics[:canonical_terms_count] = Lexicon::CanonicalTerm.where(batch_id: @batch_id).count
      end
      
      if check_entities
        metrics[:entity_counts] = {
          ideas: Idea.where(batch_id: @batch_id).count,
          manifests: Manifest.where(batch_id: @batch_id).count,
          experiences: Experience.where(batch_id: @batch_id).count,
          practicals: Practical.where(batch_id: @batch_id).count,
          emanations: Emanation.where(batch_id: @batch_id).count,
          evolutionaries: Evolutionary.where(batch_id: @batch_id).count,
          relationals: Relational.where(batch_id: @batch_id).count
        }
        metrics[:total_entities] = metrics[:entity_counts].values.sum
      end
      
      if check_graph
        begin
          graph_metrics = @neo4j.read_transaction do |tx|
            node_query = <<~CYPHER
              MATCH (n)
              WHERE n.batch_id = $batch_id
              RETURN count(n) as node_count
            CYPHER
            
            edge_query = <<~CYPHER
              MATCH (n)-[r]-(m)
              WHERE n.batch_id = $batch_id AND m.batch_id = $batch_id
              RETURN count(DISTINCT r) as edge_count
            CYPHER
            
            nodes = tx.run(node_query, batch_id: @batch_id).single[:node_count]
            edges = tx.run(edge_query, batch_id: @batch_id).single[:edge_count]
            
            { nodes: nodes, edges: edges / 2 }
          end
          
          metrics[:graph_nodes] = graph_metrics[:nodes]
          metrics[:graph_edges] = graph_metrics[:edges]
        rescue StandardError => e
          Rails.logger.error "Failed to get graph metrics: #{e.message}"
        end
      end
      
      if check_embeddings
        metrics[:embeddings_count] = Embedding.where(batch_id: @batch_id).count
      end
      
      metrics
    end
    
    def meets_requirements?(level, capabilities)
      requirements = MATURITY_LEVELS[level][:requirements]
      requirements.all? { |req| capabilities[req] == true }
    end
    
    def requirements_met(level, capabilities)
      requirements = MATURITY_LEVELS[level][:requirements]
      requirements.select { |req| capabilities[req] == true }
    end
    
    def next_level_requirements(current_level, capabilities)
      return [] if current_level == 'M6'
      
      next_level_key = "M#{current_level[1].to_i + 1}"
      next_requirements = MATURITY_LEVELS[next_level_key][:requirements]
      
      missing = next_requirements.reject { |req| capabilities[req] == true }
      
      missing.map do |req|
        {
          requirement: req,
          description: requirement_description(req),
          status: requirement_status(req, capabilities)
        }
      end
    end
    
    def requirement_description(requirement)
      case requirement
      when :has_ingest_batch
        'Ingest batch must exist'
      when :has_rights_assigned
        'Rights and provenance must be assigned to all items'
      when :has_lexicon
        'Canonical terms must be extracted'
      when :has_entities
        'Ten Pool Canon entities must be identified'
      when :has_graph
        'Knowledge graph must be assembled'
      when :has_embeddings
        'Vector embeddings must be generated'
      when :has_high_enliteracy_score
        'Enliteracy score must be ≥70'
      else
        requirement.to_s.humanize
      end
    end
    
    def requirement_status(requirement, capabilities)
      if capabilities[requirement] == true
        'complete'
      elsif capabilities[requirement] == false
        'not_started'
      else
        'in_progress'
      end
    end
    
    def level_details(level, capabilities)
      details = {
        achieved_at: nil,
        progress_to_next: 0.0,
        blockers: []
      }
      
      if level != 'M6'
        next_level_key = "M#{level[1].to_i + 1}"
        next_requirements = MATURITY_LEVELS[next_level_key][:requirements]
        met_count = next_requirements.count { |req| capabilities[req] == true }
        details[:progress_to_next] = (met_count.to_f / next_requirements.length * 100).round(2)
        
        missing = next_requirements.reject { |req| capabilities[req] == true }
        details[:blockers] = missing.map { |req| requirement_description(req) }
      else
        details[:progress_to_next] = 100.0
      end
      
      details
    end
  end
end