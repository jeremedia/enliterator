module Embedding
  class BuilderJob < ApplicationJob
    queue_as :embeddings
    
    # Job options
    STAGE_NAME = 'Stage 6: Representations & Retrieval'.freeze
    
    def perform(batch_id: nil, options: {})
      Rails.logger.info "Starting #{STAGE_NAME} for batch #{batch_id}"
      
      # Track job execution
      start_time = Time.current
      results = {
        batch_id: batch_id,
        stage: STAGE_NAME,
        started_at: start_time,
        steps: {}
      }
      
      begin
        # Determine processing mode
        use_batch_api = options[:use_batch_api] || should_use_batch_api?(batch_id)
        
        if use_batch_api && batch_id
          # Use Batch API for 50% cost savings (24-hour turnaround)
          results[:steps][:batch_api] = generate_with_batch_api(batch_id, options)
          results[:mode] = 'batch_api'
          results[:note] = 'Embeddings queued via Batch API (50% cost savings, 24hr turnaround)'
        else
          # Use synchronous API for immediate results
          results[:steps][:entity_embeddings] = generate_entity_embeddings(batch_id, options)
          results[:steps][:path_embeddings] = generate_path_embeddings(batch_id, options)
          results[:steps][:index_building] = build_indices(options)
          results[:steps][:verification] = verify_embeddings
          results[:mode] = 'synchronous'
          
          if batch_id
            update_batch_status(batch_id, 'embeddings_complete')
          end
        end
        
        results[:status] = 'success'
        results[:completed_at] = Time.current
        results[:duration] = (results[:completed_at] - start_time).round(2)
        
        # Log summary
        log_summary(results)
        
        # Trigger next stage if configured
        trigger_next_stage(batch_id) if batch_id && options[:auto_advance]
        
      rescue StandardError => e
        Rails.logger.error "#{STAGE_NAME} failed: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        
        results[:status] = 'failed'
        results[:error] = e.message
        results[:completed_at] = Time.current
        
        # Update batch status to failed
        if batch_id
          update_batch_status(batch_id, 'embeddings_failed')
        end
        
        raise # Re-raise for job retry mechanisms
      end
      
      results
    end
    
    private
    
    def should_use_batch_api?(batch_id)
      return false unless batch_id
      
      # Use Batch API for initial bulk imports
      ingest_batch = IngestBatch.find_by(id: batch_id)
      return false unless ingest_batch
      
      # Check if this is an initial import (no embeddings yet)
      existing_embeddings = ::Embedding.where(
        embeddable_id: batch_id.to_s
      ).count
      
      # Use Batch API if:
      # 1. No embeddings exist yet (initial import)
      # 2. Large number of items to process
      # 3. Not marked as urgent
      if existing_embeddings == 0 && !ingest_batch.metadata['urgent']
        item_count = estimate_item_count(batch_id)
        return item_count > 100  # Threshold for batch API
      end
      
      false
    end
    
    def estimate_item_count(batch_id)
      count = 0
      %w[Idea Manifest Experience Relational Evolutionary Practical Emanation].each do |pool|
        count += pool.constantize.where(ingest_batch_id: batch_id).count
      end
      count
    end
    
    def generate_with_batch_api(batch_id, options)
      Rails.logger.info "Using Batch API for embeddings (50% cost savings)"
      
      processor = BatchProcessor.new(
        ingest_batch_id: batch_id,
        dry_run: options[:dry_run] || false
      )
      
      results = processor.process
      
      # Queue monitoring jobs for each created batch
      results[:batches_created].each do |openai_batch_id|
        BatchMonitorJob.perform_later(
          openai_batch_id,
          ingest_batch_id: batch_id
        )
      end
      
      Rails.logger.info "Batch API: #{results[:entities_queued]} entities, #{results[:paths_queued]} paths queued"
      Rails.logger.info "Estimated cost savings: $#{results[:total_cost_savings]}"
      
      # Update batch status to indicate batch API processing
      update_batch_status(batch_id, 'embeddings_processing_batch_api')
      
      results
    end
    
    def generate_entity_embeddings(batch_id, options)
      Rails.logger.info "Generating entity embeddings..."
      
      entity_embedder = EntityEmbedder.new(
        batch_id: batch_id,
        pool_filter: options[:pool_filter],
        dry_run: options[:dry_run] || false
      )
      
      results = entity_embedder.call
      
      Rails.logger.info "Entity embeddings: #{results[:processed]} processed, #{results[:errors]} errors"
      
      results
    end
    
    def generate_path_embeddings(batch_id, options)
      Rails.logger.info "Generating path embeddings..."
      
      path_embedder = PathEmbedder.new(
        batch_id: batch_id,
        pool_filter: options[:pool_filter],
        dry_run: options[:dry_run] || false,
        max_paths: options[:max_paths] || 1000
      )
      
      results = path_embedder.call
      
      Rails.logger.info "Path embeddings: #{results[:processed]} processed, #{results[:errors]} errors"
      
      results
    end
    
    def build_indices(options)
      Rails.logger.info "Building/optimizing indices..."
      
      index_builder = IndexBuilder.new(
        index_type: options[:index_type] || 'hnsw',
        force_rebuild: options[:force_rebuild] || false
      )
      
      results = index_builder.call
      
      # Set optimal search parameters
      IndexBuilder.optimize_for_search(quality: options[:search_quality] || 'balanced')
      
      Rails.logger.info "Index building: #{results[:status]}"
      
      results
    end
    
    def verify_embeddings
      Rails.logger.info "Verifying embeddings quality..."
      
      verification = {
        coverage: ::Embedding.coverage_stats,
        sample_searches: perform_sample_searches
      }
      
      # Check for minimum coverage
      total_entities = count_total_entities
      embedded_entities = ::Embedding.entities.count
      coverage_percent = (embedded_entities.to_f / total_entities * 100).round(2)
      
      verification[:coverage_percent] = coverage_percent
      verification[:meets_threshold] = coverage_percent >= 90 # 90% coverage threshold
      
      Rails.logger.info "Embedding coverage: #{coverage_percent}%"
      
      verification
    end
    
    def perform_sample_searches
      # Test a few sample searches to ensure the index is working
      samples = []
      
      # Test entity search
      test_entity = ::Embedding.entities.first
      if test_entity
        similar = test_entity.find_similar(limit: 5)
        samples << {
          type: 'entity_similarity',
          source_id: test_entity.id,
          found: similar.count,
          success: similar.any?
        }
      end
      
      # Test path search
      test_path = ::Embedding.paths.first
      if test_path
        similar = test_path.find_similar(limit: 5)
        samples << {
          type: 'path_similarity',
          source_id: test_path.id,
          found: similar.count,
          success: similar.any?
        }
      end
      
      samples
    end
    
    def count_total_entities
      total = 0
      
      %w[Idea Manifest Experience Relational Evolutionary Practical Emanation].each do |pool|
        model_class = pool.constantize
        total += model_class.where(training_eligible: true)
                           .where.not(repr_text: [nil, ''])
                           .count
      end
      
      total
    end
    
    def update_batch_status(batch_id, status)
      batch = IngestBatch.find_by(id: batch_id)
      return unless batch
      
      batch.update!(
        status: status,
        metadata: batch.metadata.merge(
          embeddings_completed_at: Time.current,
          embeddings_count: ::Embedding.where(
            embeddable_id: batch.id.to_s
          ).count
        )
      )
    end
    
    def log_summary(results)
      Rails.logger.info <<~SUMMARY
        
        ========== #{STAGE_NAME} Complete ==========
        Batch ID: #{results[:batch_id] || 'N/A'}
        Duration: #{results[:duration]}s
        
        Entity Embeddings:
          - Processed: #{results[:steps][:entity_embeddings][:processed]}
          - Errors: #{results[:steps][:entity_embeddings][:errors]}
        
        Path Embeddings:
          - Processed: #{results[:steps][:path_embeddings][:processed]}
          - Errors: #{results[:steps][:path_embeddings][:errors]}
        
        Index:
          - Type: #{results[:steps][:index_building][:index_type]}
          - Status: #{results[:steps][:index_building][:status]}
        
        Coverage:
          - Entities: #{results[:steps][:verification][:coverage_percent]}%
          - Meets Threshold: #{results[:steps][:verification][:meets_threshold]}
        
        Total Embeddings: #{::Embedding.count}
        ==========================================
      SUMMARY
    end
    
    def trigger_next_stage(batch_id)
      # Queue the next stage job (Stage 7: Literacy Scoring)
      # This will be implemented when Stage 7 is built
      Rails.logger.info "Ready for Stage 7: Literacy Scoring & Gaps"
      
      # Placeholder for next stage
      # Literacy::ScoringJob.perform_later(batch_id: batch_id)
    end
  end
end