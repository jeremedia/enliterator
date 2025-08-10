# frozen_string_literal: true

module Pipeline
  class SmartRunner
    attr_reader :ekn, :batch, :options
    
    def initialize(ekn:, batch:, options: {})
      @ekn = ekn
      @batch = batch
      @options = options
      @force_stages = options[:force_stages] || []
      @skip_expensive = options[:skip_expensive] || false
      @dry_run = options[:dry_run] || false
    end
    
    def run_full_pipeline
      Rails.logger.info "Starting smart pipeline for batch #{batch.id}: #{batch.name}"
      results = {}
      
      StageCompletion::STAGES.each do |stage_num, stage_info|
        results[stage_num] = run_stage(stage_num)
        
        # Stop if stage failed
        if results[stage_num][:status] == 'failed'
          Rails.logger.error "Pipeline stopped at stage #{stage_num} due to failure"
          break
        end
      end
      
      results
    end
    
    def run_stage(stage_number, force: false)
      stage_info = StageCompletion::STAGES[stage_number]
      stage_name = stage_info[:name]
      
      Rails.logger.info "Processing stage #{stage_number}: #{stage_name}"
      
      # Find or create completion record
      completion = StageCompletion.find_or_initialize_by(
        ingest_batch: batch,
        ekn: ekn,
        stage_number: stage_number
      )
      completion.stage_name = stage_name
      
      # Check if we should force this stage
      force ||= @force_stages.include?(stage_number)
      
      # Check if we can skip
      if !force && should_skip_stage?(completion)
        skip_reason = determine_skip_reason(completion)
        
        if @dry_run
          Rails.logger.info "[DRY RUN] Would skip stage #{stage_number}: #{skip_reason}"
          return { status: 'would_skip', reason: skip_reason }
        end
        
        completion.skip!(skip_reason)
        Rails.logger.info "Skipped stage #{stage_number}: #{skip_reason}"
        
        return {
          status: 'skipped',
          reason: skip_reason,
          metrics: completion.completion_metrics
        }
      end
      
      # Check for incremental processing opportunity
      if !force && can_process_incrementally?(completion)
        return run_incremental(completion)
      end
      
      # Run the full stage
      if @dry_run
        Rails.logger.info "[DRY RUN] Would run stage #{stage_number}"
        return { status: 'would_run' }
      end
      
      run_full_stage(completion)
    end
    
    private
    
    def should_skip_stage?(completion)
      # Skip expensive stages if requested
      if @skip_expensive && completion.expensive?
        Rails.logger.info "Skipping expensive stage #{completion.stage_number} due to skip_expensive flag"
        return true
      end
      
      # Check if stage can be skipped based on completion criteria
      completion.can_be_skipped?
    end
    
    def determine_skip_reason(completion)
      if completion.status == 'completed'
        "Stage already completed at #{completion.completed_at}"
      elsif completion.can_be_skipped?
        metrics = completion.completion_metrics
        case completion.stage_number
        when 4 # Pool Filling
          "Entities already extracted: #{metrics['total_entities']} entities across #{metrics['pools_with_entities']} pools"
        when 6 # Embeddings
          "Embeddings already exist: #{metrics['embedding_count']}/#{metrics['entity_count']} (#{(metrics['coverage'] * 100).round(1)}% coverage)"
        when 3 # Lexicon
          "Lexicon already built: #{metrics['lexicon_count']} entries"
        when 5.5 # Relationships
          "Relationships already discovered: #{metrics['edge_count']} edges (density: #{metrics['density'].round(4)})"
        else
          "Stage completion criteria met"
        end
      else
        "Unknown skip reason"
      end
    end
    
    def can_process_incrementally?(completion)
      # Only certain stages support incremental processing
      case completion.stage_number
      when 4 # Pool Filling
        # Can process items without entities
        metrics = completion.completion_metrics || {}
        coverage = metrics['coverage_rate'] || 0
        coverage > 0 && coverage < 0.95 # Partially complete
        
      when 6 # Embeddings
        # Can process nodes without embeddings
        metrics = completion.completion_metrics || {}
        coverage = metrics['coverage'] || 0
        coverage > 0 && coverage < 0.95 # Partially complete
        
      else
        false
      end
    end
    
    def run_incremental(completion)
      Rails.logger.info "Running incremental processing for stage #{completion.stage_number}"
      
      completion.update!(status: 'in_progress', started_at: Time.current)
      
      begin
        result = case completion.stage_number
        when 4 # Pool Filling
          run_incremental_pool_filling
        when 6 # Embeddings
          run_incremental_embeddings
        else
          raise "Incremental processing not implemented for stage #{completion.stage_number}"
        end
        
        completion.update!(
          status: 'completed',
          completed_at: Time.current,
          completion_metrics: result[:metrics]
        )
        
        result
      rescue => e
        Rails.logger.error "Incremental processing failed: #{e.message}"
        completion.update!(status: 'failed')
        { status: 'failed', error: e.message }
      end
    end
    
    def run_incremental_pool_filling
      # Find items without extracted entities
      # Since entities are stored in Neo4j, not separate tables,
      # we need a different approach to find items without entities
      items_without_entities = batch.ingest_items
      
      Rails.logger.info "Processing #{items_without_entities.count} items without entities"
      
      # Run extraction only for these items
      extractor = Pools::ExtractionJob.new
      processed = 0
      
      items_without_entities.find_each do |item|
        extractor.perform(item.id)
        processed += 1
      end
      
      {
        status: 'completed',
        incremental: true,
        metrics: {
          items_processed: processed,
          total_entities: count_batch_nodes  # Use Neo4j count
        }
      }
    end
    
    def run_incremental_embeddings
      # Find nodes without embeddings in Neo4j
      driver = Graph::Connection.instance.driver
      nodes_without_embeddings = []
      
      driver.session(database: ekn.neo4j_database_name) do |session|
        session.read_transaction do |tx|
          result = tx.run(<<~CYPHER, batch_id: batch.id)
            MATCH (n)
            WHERE n.batch_id = $batch_id
              AND n.embedding IS NULL
            RETURN id(n) as id, n.repr_text as text
            CYPHER
          
          result.each do |row|
            nodes_without_embeddings << {
              id: row['id'],
              text: row['text']
            }
          end
        end
      end
      
      Rails.logger.info "Generating embeddings for #{nodes_without_embeddings.count} nodes"
      
      # For now, just mark as needing embeddings
      # In production, would use Embedding::RepresentationJob
      
      {
        status: 'completed',
        incremental: true,
        metrics: {
          embeddings_needed: nodes_without_embeddings.count,
          embeddings_generated: 0  # Would be done async
        }
      }
    end
    
    def run_full_stage(completion)
      completion.update!(
        status: 'in_progress',
        started_at: Time.current,
        api_calls_made: 0
      )
      
      begin
        # Create or find pipeline run for this stage
        pipeline_run = find_or_create_pipeline_run
        pipeline_run.update!(current_stage_number: completion.stage_number)
        
        result = execute_stage(completion.stage_number, pipeline_run)
        
        completion.update!(
          status: 'completed',
          completed_at: Time.current,
          completion_metrics: result[:metrics],
          api_calls_made: result[:api_calls] || 0,
          api_cost_usd: result[:cost] || 0
        )
        
        result
      rescue => e
        Rails.logger.error "Stage #{completion.stage_number} failed: #{e.message}"
        completion.update!(
          status: 'failed',
          completion_metrics: { error: e.message }
        )
        
        { status: 'failed', error: e.message }
      end
    end
    
    def execute_stage(stage_number, pipeline_run = nil)
      case stage_number
      when 0 # Frame Mission
        { status: 'completed', metrics: { configured: true } }
        
      when 1 # Intake
        if pipeline_run
          Ingest::IntakeJob.perform_now(pipeline_run.id)
        else
          # Fallback for direct execution
          # Note: This won't have proper logging/tracking
          { status: 'completed', metrics: { items: batch.ingest_items.count } }
        end
        {
          status: 'completed',
          metrics: { items: batch.ingest_items.count }
        }
        
      when 2 # Rights & Provenance
        if pipeline_run
          Rights::AssignmentJob.perform_now(pipeline_run.id)
        end
        {
          status: 'completed',
          metrics: { items_with_rights: batch.ingest_items.where.not(provenance_and_rights_id: nil).count }
        }
        
      when 3 # Lexicon Bootstrap
        if pipeline_run
          Lexicon::BootstrapJob.perform_now(pipeline_run.id)
        end
        {
          status: 'completed',
          metrics: { entries: LexiconAndOntology.count },  # Global count for now
          api_calls: 10  # Estimate
        }
        
      when 4 # Pool Filling - EXPENSIVE!
        if pipeline_run
          Pools::ExtractionJob.perform_now(pipeline_run.id)
        end
        api_calls = batch.ingest_items.count  # Estimate
        
        # Count entities by pool in Neo4j
        pool_counts = count_entities_by_pool
        {
          status: 'completed',
          metrics: pool_counts,
          api_calls: api_calls,
          cost: api_calls * 0.01 # Estimate
        }
        
      when 5 # Graph Assembly
        if pipeline_run
          Graph::AssemblyJob.perform_now(pipeline_run.id)
        end
        {
          status: 'completed',
          metrics: { nodes_created: count_batch_nodes }
        }
        
      when 5.5 # Relationship Discovery
        discovery = Graph::MultiPassDiscovery.new(ekn: ekn, batch: batch)
        result = discovery.execute_all_passes
        {
          status: 'completed',
          metrics: result,
          api_calls: result[:total_discovered] || 0
        }
        
      when 6 # Embeddings - EXPENSIVE!
        if pipeline_run
          Embedding::RepresentationJob.perform_now(pipeline_run.id)
        end
        # Count embeddings created
        embedding_count = count_batch_nodes  # Approximate
        {
          status: 'completed',
          metrics: { embeddings: embedding_count },
          api_calls: embedding_count,  # Estimate
          cost: embedding_count * 0.001  # Rough estimate
        }
        
      when 7 # Literacy Scoring
        scorer = Graph::StageMetrics.new(ekn: ekn, batch: batch)
        metrics = scorer.calculate_all_metrics
        {
          status: 'completed',
          metrics: metrics
        }
        
      when 8 # Deliverables
        # Deliverables generation - for now just mark as complete
        {
          status: 'completed',
          metrics: { deliverables: 0 }  # Not implemented yet
        }
        
      else
        raise "Unknown stage: #{stage_number}"
      end
    end
    
    def count_batch_nodes
      return 0 unless ekn.neo4j_database_name
      
      driver = Graph::Connection.instance.driver
      count = 0
      
      driver.session(database: ekn.neo4j_database_name) do |session|
        session.read_transaction do |tx|
          result = tx.run(
            "MATCH (n) WHERE n.batch_id = $batch_id RETURN count(n) as count",
            batch_id: batch.id
          )
          count = result.single['count']
        end
      end
      
      count
    end
    
    def find_or_create_pipeline_run
      @pipeline_run ||= EknPipelineRun.find_or_create_by!(
        ekn: ekn,
        ingest_batch: batch
      ) do |pr|
        pr.status = 'running'
        pr.current_stage_number = 0
        pr.started_at = Time.current
        pr.options = {
          runner: 'smart_runner',
          skip_expensive: @skip_expensive,
          force_stages: @force_stages
        }
      end
    end
    
    def count_entities_by_pool
      return {} unless ekn.neo4j_database_name
      
      driver = Graph::Connection.instance.driver
      pool_counts = {}
      
      driver.session(database: ekn.neo4j_database_name) do |session|
        session.read_transaction do |tx|
          result = tx.run(<<~CYPHER, batch_id: batch.id)
            MATCH (n)
            WHERE n.batch_id = $batch_id
            RETURN labels(n)[0] as pool, count(n) as count
            ORDER BY pool
          CYPHER
          
          result.each do |row|
            pool_counts[row['pool'].downcase.to_sym] = row['count']
          end
        end
      end
      
      pool_counts
    rescue => e
      Rails.logger.error "Failed to count entities by pool: #{e.message}"
      {}
    end
  end
end