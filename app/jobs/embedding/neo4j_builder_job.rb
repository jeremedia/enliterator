# frozen_string_literal: true

module Embedding
  # Neo4j-based embedding builder job (replaces pgvector version)
  class Neo4jBuilderJob < ApplicationJob
    queue_as :embeddings
    
    STAGE_NAME = 'Stage 6: Representations & Retrieval (Neo4j)'.freeze
    
    def perform(batch_id: nil, options: {})
      Rails.logger.info "Starting #{STAGE_NAME} for batch #{batch_id}"
      
      start_time = Time.current
      results = {
        batch_id: batch_id,
        stage: STAGE_NAME,
        started_at: start_time,
        steps: {}
      }
      
      begin
        # Initialize Neo4j embedding service
        embedding_service = ::Neo4j::EmbeddingService.new(batch_id)
        
        # Step 1: Build vector indexes
        results[:steps][:index_building] = build_indices(embedding_service)
        
        # Step 2: Generate entity embeddings
        results[:steps][:entity_embeddings] = generate_entity_embeddings(embedding_service, options)
        
        # Step 3: Generate path embeddings
        results[:steps][:path_embeddings] = generate_path_embeddings(embedding_service, options)
        
        # Step 4: Verify embeddings
        results[:steps][:verification] = verify_embeddings(embedding_service)
        
        # Update batch status
        if batch_id
          batch = IngestBatch.find(batch_id)
          batch.update!(
            status: 'embeddings_complete',
            embedding_stats: results[:steps][:verification]
          )
        end
        
        results[:status] = 'success'
        results[:completed_at] = Time.current
        results[:duration] = (results[:completed_at] - start_time).round(2)
        
        log_summary(results)
        
        # Trigger next stage if configured
        trigger_next_stage(batch_id) if batch_id && options[:auto_advance]
        
      rescue StandardError => e
        Rails.logger.error "#{STAGE_NAME} failed: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        
        results[:status] = 'failed'
        results[:error] = e.message
        results[:completed_at] = Time.current
        
        if batch_id
          batch = IngestBatch.find(batch_id)
          batch.update!(status: 'embeddings_failed', error_message: e.message)
        end
        
        raise # Re-raise for job retry
      end
      
      results
    end
    
    private
    
    def build_indices(embedding_service)
      Rails.logger.info "Building vector indexes..."
      start = Time.current
      
      embedding_service.build_indices
      
      {
        status: 'completed',
        duration: (Time.current - start).round(2),
        note: 'Neo4j vector indexes created'
      }
    end
    
    def generate_entity_embeddings(embedding_service, options)
      Rails.logger.info "Generating entity embeddings..."
      start = Time.current
      
      batch_size = options[:batch_size] || 100
      total_processed = 0
      
      # Process in batches until no more entities need embeddings
      loop do
        processed = embedding_service.generate_entity_embeddings(limit: batch_size)
        total_processed += processed
        break if processed < batch_size
      end
      
      {
        status: 'completed',
        total_processed: total_processed,
        duration: (Time.current - start).round(2),
        note: "Generated embeddings for #{total_processed} entities"
      }
    end
    
    def generate_path_embeddings(embedding_service, options)
      Rails.logger.info "Generating path embeddings..."
      start = Time.current
      
      batch_size = options[:batch_size] || 100
      total_processed = 0
      
      # Process in batches until no more paths need embeddings
      loop do
        processed = embedding_service.generate_path_embeddings(limit: batch_size)
        total_processed += processed
        break if processed < batch_size
      end
      
      {
        status: 'completed',
        total_processed: total_processed,
        duration: (Time.current - start).round(2),
        note: "Generated embeddings for #{total_processed} paths"
      }
    end
    
    def verify_embeddings(embedding_service)
      Rails.logger.info "Verifying embeddings..."
      
      verification_results = embedding_service.verify_embeddings
      
      Rails.logger.info "Embeddings verified: #{verification_results[:total_embeddings]} total"
      Rails.logger.info "Pools with embeddings: #{verification_results[:pools_with_embeddings]&.join(', ')}"
      
      verification_results
    end
    
    def log_summary(results)
      Rails.logger.info "=" * 80
      Rails.logger.info "#{STAGE_NAME} Summary"
      Rails.logger.info "=" * 80
      Rails.logger.info "Status: #{results[:status]}"
      Rails.logger.info "Duration: #{results[:duration]}s"
      
      if results[:steps][:entity_embeddings]
        Rails.logger.info "Entity Embeddings: #{results[:steps][:entity_embeddings][:total_processed]}"
      end
      
      if results[:steps][:path_embeddings]
        Rails.logger.info "Path Embeddings: #{results[:steps][:path_embeddings][:total_processed]}"
      end
      
      if results[:steps][:verification]
        Rails.logger.info "Total Embeddings: #{results[:steps][:verification][:total_embeddings]}"
      end
      
      Rails.logger.info "=" * 80
    end
    
    def trigger_next_stage(batch_id)
      Rails.logger.info "Triggering Stage 7: Literacy Scoring & Gaps..."
      Literacy::ScoringJob.perform_later(batch_id: batch_id)
    end
  end
end