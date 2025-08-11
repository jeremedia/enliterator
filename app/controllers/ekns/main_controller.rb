module Ekns
  class MainController < ApplicationController
    before_action :load_ekn
    
    def show
      # Landing page - Beautiful overview with key stats
      @stats = EknStatsService.new(@ekn).basic_stats
      @recent_activity = @ekn.conversations.includes(:messages).limit(3)
    end
    
    def dashboard
      # Ultra-impressive dashboard with all visualizations
      include_provenance = params[:include_provenance] == 'true'
      @stats_service = EknStatsService.new(@ekn, include_provenance: include_provenance)
      @stats = @stats_service.comprehensive_stats
      @network_data = @stats_service.network_visualization_data
      @chord_data = @stats_service.chord_diagram_data
      @timeline_data = @stats_service.temporal_data
      @pool_distribution = @stats_service.pool_distribution
      @relationship_matrix = @stats_service.relationship_matrix
      @relationship_heatmap_data = @stats_service.relationship_matrix_heatmap_data
      @top_entities = @stats_service.most_connected_entities
      @include_provenance = include_provenance
    end

    def training
      # Training methodology page
      @personality_profile = @ekn.ekn_personality_profile
      @training_sets = @ekn.training_question_sets.includes(:training_questions)
      @stats = {
        total_questions: @ekn.training_questions.count,
        active_questions: @ekn.training_questions.where(active: true).count,
        question_types: @ekn.training_questions.group(:question_type).count,
        difficulty_levels: @ekn.training_questions.group(:difficulty_level).count,
        archetype_focuses: @ekn.training_questions.group(:archetype_focus).count
      }
    end

    def pipeline
      @stats_service = EknStatsService.new(@ekn)
      @basic = @stats_service.basic_stats
      @batches = @ekn.ingest_batches.includes(:ingest_items, :stage_completions).order(created_at: :desc)

      # Aggregate inputs
      @input = {
        total_batches: @batches.size,
        total_items: @ekn.ingest_items.count,
        media_types: @ekn.ingest_items.group(:media_type).count,
        quarantined: @ekn.ingest_items.where(triage_status: 'quarantined').count
      }

      # Rights summary
      rights_ids = @ekn.ingest_items.where.not(provenance_and_rights_id: nil).distinct.pluck(:provenance_and_rights_id)
      rights_scope = ProvenanceAndRights.where(id: rights_ids)
      @rights = {
        total_rights_records: rights_scope.count,
        publishable: rights_scope.where(publishability: true).count,
        training_eligible: rights_scope.where(training_eligibility: true).count,
        embargoed: rights_scope.embargoed.count
      }

      # Stage metrics (lightweight, academic audience)
      @stages = []
      # Stage 1 Intake
      @stages << {
        number: 1, name: 'Intake', description: 'Bundle discovery, MIME routing, hashing, content capture',
        status: stage_status_aggregate(@batches, 1), metrics: { items: @input[:total_items] }
      }
      # Stage 2 Rights
      @stages << {
        number: 2, name: 'Rights & Provenance', description: 'Consent, license inference, quarantines, eligibility gates',
        status: stage_status_aggregate(@batches, 2), metrics: @rights
      }
      # Stage 3 Lexicon
      lex_count = LexiconAndOntology.where(provenance_and_rights_id: rights_ids).count rescue 0
      @stages << {
        number: 3, name: 'Lexicon Bootstrap', description: 'Canonical terms, surface forms, normalization',
        status: stage_status_aggregate(@batches, 3), metrics: { lexicon_entries: lex_count }
      }
      # Stage 4 Pools
      entities_extracted = @ekn.ingest_items.sum("(pool_metadata->>'entities_count')::int") rescue 0
      @stages << {
        number: 4, name: 'Pool Filling', description: 'Ten Pool Canon entity extraction (OpenAI Structured Outputs)',
        status: stage_status_aggregate(@batches, 4), metrics: { entities_extracted: entities_extracted }
      }
      # Stage 5 Graph
      @stages << {
        number: 5, name: 'Graph Assembly', description: 'Neo4j node/edge load, constraints, deduplication',
        status: stage_status_aggregate(@batches, 5), metrics: { nodes: @basic[:total_nodes], relationships: @basic[:total_relationships] }
      }
      # Stage 5.5 Relationships
      rel_stats = latest_stage_metrics(@batches, 5.5)
      @stages << {
        number: 5.5, name: 'Relationship Discovery', description: 'Cluster-based cross-boundary relation discovery (LLM-assisted)',
        status: stage_status_aggregate(@batches, 5.5), metrics: rel_stats.presence || { density: 'n/a' }
      }
      # Stage 6 Embeddings
      begin
        emb_count = 0
        Graph::Connection.instance.driver.session(database: @ekn.neo4j_database_name) do |session|
          emb_count = session.run("MATCH (n) WHERE exists(n.embedding) RETURN count(n) as c").single['c']
        end
      rescue
        emb_count = 0
      end
      @stages << {
        number: 6, name: 'Embeddings', description: 'Neo4j GenAI unified vector representations',
        status: stage_status_aggregate(@batches, 6), metrics: { embedded_nodes: emb_count }
      }
      # Stage 7 Literacy
      @stages << {
        number: 7, name: 'Literacy Scoring', description: 'Coverage, grounding, rights-first phrasing, gap analysis',
        status: stage_status_aggregate(@batches, 7), metrics: { literacy_score: @ekn.literacy_score }
      }
      # Stage 8 Deliverables
      deliv = @batches.map { |b| b.deliverables&.size || 0 }.sum
      @stages << {
        number: 8, name: 'Deliverables', description: 'Reports, maps, timelines, tables, storyboards',
        status: stage_status_aggregate(@batches, 8), metrics: { deliverables: deliv }
      }
    end
    
    def entity
      # Entity details for popover/modal
      @entity = EknEntityService.new(@ekn).get_entity_details(params[:id])
      render json: @entity
    rescue => e
      render json: { error: e.message }, status: 404
    end
    
    private
    
    def load_ekn
      @ekn = ::Ekn.find_by!(slug: params[:ekn_slug])
    end

    def stage_status_aggregate(batches, stage_number)
      statuses = batches.flat_map { |b| b.stage_completions.where(stage_number: stage_number).pluck(:status) }
      return 'pending' if statuses.empty?
      if statuses.all? { |s| s == 'completed' }
        'completed'
      elsif statuses.any? { |s| s == 'failed' }
        'failed'
      elsif statuses.any? { |s| s == 'in_progress' }
        'in_progress'
      else
        statuses.first
      end
    end

    def latest_stage_metrics(batches, stage_number)
      rec = batches.map { |b| b.stage_completions.where(stage_number: stage_number).order(updated_at: :desc).first }.compact.first
      rec&.completion_metrics
    end
  end
end
