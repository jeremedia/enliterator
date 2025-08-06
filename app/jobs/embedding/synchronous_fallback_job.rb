module EmbeddingServices
  class SynchronousFallbackJob < ApplicationJob
    queue_as :embeddings
    
    # Fallback job to process failed batch API requests synchronously
    
    def perform(failed_ids:, ingest_batch_id: nil)
      Rails.logger.info "Processing #{failed_ids.size} failed items synchronously"
      
      processed = 0
      failed = 0
      
      failed_ids.each do |custom_id|
        begin
          # Parse custom ID to determine type
          if custom_id.start_with?('entity-')
            process_entity(custom_id, ingest_batch_id)
          elsif custom_id.start_with?('path-')
            process_path(custom_id, ingest_batch_id)
          else
            Rails.logger.warn "Unknown custom ID format: #{custom_id}"
            next
          end
          
          processed += 1
        rescue => e
          Rails.logger.error "Failed to process #{custom_id}: #{e.message}"
          failed += 1
        end
      end
      
      Rails.logger.info "Synchronous fallback complete: #{processed} processed, #{failed} failed"
      
      { processed: processed, failed: failed }
    end
    
    private
    
    def process_entity(custom_id, ingest_batch_id)
      # Parse entity info from custom ID
      # Format: "entity-PoolName-ID"
      parts = custom_id.split('-')
      pool_name = parts[1]
      entity_id = parts[2]
      
      # Find the entity
      model_class = pool_name.constantize
      entity = model_class.find(entity_id)
      
      # Skip if already has embedding
      existing = ::Embedding.find_by(
        embeddable_type: pool_name,
        embeddable_id: entity_id,
        embedding_type: 'entity'
      )
      return if existing
      
      # Generate embedding synchronously
      response = OPENAI.embeddings.create(
        input: entity.repr_text,
        model: ::Embedding::OPENAI_MODEL,
        dimensions: ::Embedding::OPENAI_DIMENSIONS
      )
      
      embedding_vector = response.data.first.embedding
      
      # Create embedding record
      ::Embedding.create!(
        embeddable_type: pool_name,
        embeddable_id: entity.id,
        pool: pool_name.downcase,
        embedding_type: 'entity',
        source_text: entity.repr_text,
        text_hash: Digest::SHA256.hexdigest(entity.repr_text),
        embedding: embedding_vector,
        publishable: entity.publishable,
        training_eligible: entity.training_eligible,
        metadata: {
          canonical_name: entity.canonical_name,
          synchronous_fallback: true,
          original_batch_failed: true
        },
        model_version: ::Embedding::OPENAI_MODEL,
        indexed_at: Time.current
      )
      
      Rails.logger.info "Created embedding for #{custom_id} via synchronous fallback"
    end
    
    def process_path(custom_id, ingest_batch_id)
      # For paths, we need to reconstruct from the hash
      # This is more complex and might need additional metadata storage
      Rails.logger.warn "Path fallback not fully implemented for #{custom_id}"
      
      # In production, you'd want to store path data when creating batch requests
      # so it can be retrieved here for fallback processing
    end
  end
end