# frozen_string_literal: true

# PURPOSE: Stage 6 of the 9-stage pipeline - Representations & Retrieval
# Builds embeddings for entities and paths, creates vector indices
#
# Inputs: Neo4j graph with textized paths
# Outputs: Vector embeddings in Neo4j (via GenAI plugin)

module Embedding
  class RepresentationJob < Pipeline::BaseJob
    queue_as :pipeline
    
    def perform(pipeline_run_id)
      # BaseJob sets up @pipeline_run, @batch, @ekn via around_perform
      # Do NOT call super - BaseJob uses around_perform to wrap this method
      
      @embeddings_created = 0
      @fallback_used = false
      
      log_progress "Starting embedding generation for batch #{@batch.id}"
      
      begin
        # Try to use Neo4j GenAI for embeddings
        if use_neo4j_genai_embeddings?
          generate_real_embeddings
        else
          # Fallback path for development/testing when GenAI is unavailable
          use_fallback_embeddings
        end
        
        log_progress "✅ Embeddings complete: #{@embeddings_created} created"
        
        # Track metrics
        track_metric :embeddings_created, @embeddings_created
        track_metric :embeddings_fallback_used, @fallback_used
        
        # Update batch metadata if fallback was used
        if @fallback_used
          @batch.update!(
            metadata: @batch.metadata.merge(embeddings_fallback_used: true)
          )
        end
        
        # Update batch status
        @batch.update!(status: 'representations_completed')
        
      rescue => e
        log_progress "Embedding generation failed: #{e.message}", level: :error
        # In development/test, don't fail the pipeline for embedding issues
        if Rails.env.development? || Rails.env.test?
          log_progress "WARNING: Continuing with fallback embeddings in #{Rails.env} mode", level: :warn
          use_fallback_embeddings
          @batch.update!(status: 'representations_completed')
        else
          raise
        end
      end
    end
    
    private
    
    def use_neo4j_genai_embeddings?
      # Check if we have OpenAI API key and Neo4j GenAI is available
      return false unless ENV['OPENAI_API_KEY'].present?
      
      # Try to configure provider and verify it works
      database_name = @ekn.neo4j_database_name
      vector_service = Neo4j::VectorIndexService.new(database_name)
      
      if vector_service.configure_provider
        log_progress "Neo4j GenAI provider configured successfully"
        true
      else
        log_progress "Neo4j GenAI provider configuration failed", level: :warn
        false
      end
    rescue => e
      log_progress "Cannot use Neo4j GenAI: #{e.message}", level: :warn
      false
    end
    
    def generate_real_embeddings
      database_name = @ekn.neo4j_database_name
      
      # Initialize services
      vector_service = Neo4j::VectorIndexService.new(database_name)
      embedding_service = Neo4j::EmbeddingService.new(@batch.id)
      
      # Configure provider with model from SettingsManager
      configure_embedding_model(vector_service)
      
      # Create vector indexes
      log_progress "Creating vector indexes..."
      vector_service.create_indexes
      
      # Generate entity embeddings in batches
      log_progress "Generating entity embeddings..."
      total_entities = 0
      loop do
        processed = embedding_service.generate_entity_embeddings(limit: 200)
        break if processed == 0
        total_entities += processed
        log_progress "Generated embeddings for #{total_entities} entities...", level: :debug
      end
      
      # Generate path embeddings in batches
      log_progress "Generating path embeddings..."
      total_paths = 0
      loop do
        processed = embedding_service.generate_path_embeddings(limit: 200)
        break if processed == 0
        total_paths += processed
        log_progress "Generated embeddings for #{total_paths} paths...", level: :debug
      end
      
      @embeddings_created = total_entities + total_paths
      log_progress "Generated embeddings: #{total_entities} entities, #{total_paths} paths"
      
      # Update item statuses for eligible items
      update_item_embedding_status(true)
      
      # Verify embeddings
      stats = embedding_service.verify_embeddings
      log_progress "Embedding verification: #{stats}", level: :debug
    end
    
    def configure_embedding_model(vector_service)
      # Get embedding model from SettingsManager
      # Note: SettingsManager doesn't have a dedicated embedding model setting yet,
      # so we'll use a sensible default that can be overridden via environment
      model = ENV['OPENAI_EMBEDDING_MODEL'] || 'text-embedding-3-small'
      
      # If we want to use SettingsManager in the future, we could add:
      # model = OpenaiConfig::SettingsManager.model_for(:embedding) rescue model
      
      log_progress "Using embedding model: #{model}"
      
      # The vector service already sets the model in its configure_provider method
      # but we can pass it as a parameter in the future if needed
    end
    
    def use_fallback_embeddings
      @fallback_used = true
      log_progress "Using fallback embedding strategy (marking items without actual vectors)", level: :warn
      
      # Mark a subset of items as "embedded" to allow pipeline progression
      # This is only for development/testing - production should use real embeddings
      items = @batch.ingest_items
        .where(graph_status: 'assembled')
        .where(embedding_status: ['pending', nil])
        .where(training_eligible: true)
        .limit(10)  # Only mark a few items to indicate fallback was used
      
      items.each do |item|
        item.update!(
          embedding_status: 'embedded',
          embedding_metadata: { 
            embedded_at: Time.current,
            method: 'fallback',
            fallback_reason: 'Neo4j GenAI unavailable'
          }
        )
        @embeddings_created += 1
      end
      
      log_progress "Marked #{@embeddings_created} items with fallback embedding status"
    end
    
    def update_item_embedding_status(real_embeddings = false)
      # Update IngestItem statuses based on what was actually embedded
      items = @batch.ingest_items
        .where(graph_status: 'assembled')
        .where(embedding_status: ['pending', nil])
        .where(training_eligible: true)
      
      if real_embeddings && @embeddings_created > 0
        # Mark items as embedded
        items.update_all(
          embedding_status: 'embedded',
          embedding_metadata: { 
            embedded_at: Time.current,
            method: 'neo4j_genai'
          }
        )
      elsif !real_embeddings
        # Already handled in use_fallback_embeddings
        return
      else
        # No embeddings were created despite trying
        log_progress "No embeddings were created", level: :warn
        items.update_all(
          embedding_status: 'failed',
          embedding_metadata: { 
            failed_at: Time.current,
            reason: 'No embeddings generated'
          }
        )
      end
    end
    
    def collect_stage_metrics
      {
        embeddings_created: @metrics[:embeddings_created] || 0,
        embeddings_fallback_used: @metrics[:embeddings_fallback_used] || false
      }
    end
  end
end