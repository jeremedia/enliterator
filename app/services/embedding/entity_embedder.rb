module EmbeddingServices
  class EntityEmbedder
    include ActiveModel::Model
    
    # Batch processing configuration
    BATCH_SIZE = 100
    MAX_RETRIES = 3
    RETRY_DELAY = 2
    
    attr_accessor :batch_id, :pool_filter, :dry_run
    
    def initialize(batch_id: nil, pool_filter: nil, dry_run: false)
      @batch_id = batch_id
      @pool_filter = pool_filter
      @dry_run = dry_run
      @processed_count = 0
      @error_count = 0
      @skipped_count = 0
    end
    
    def call
      Rails.logger.info "Starting entity embedding generation for batch #{batch_id}"
      
      # Find entities that need embeddings
      entities = find_entities_needing_embeddings
      
      if entities.empty?
        Rails.logger.info "No entities need embeddings"
        return { processed: 0, errors: 0, skipped: 0 }
      end
      
      Rails.logger.info "Found #{entities.count} entities needing embeddings"
      
      # Process in batches for efficiency
      entities.find_in_batches(batch_size: BATCH_SIZE) do |batch|
        process_batch(batch)
      end
      
      {
        processed: @processed_count,
        errors: @error_count,
        skipped: @skipped_count
      }
    end
    
    private
    
    def find_entities_needing_embeddings
      # Build base query for entities with repr_text but no embeddings
      base_query = build_base_query
      
      # Apply pool filter if specified
      base_query = base_query.where(pool: @pool_filter) if @pool_filter.present?
      
      # Apply batch filter if specified
      base_query = base_query.where(ingest_batch_id: @batch_id) if @batch_id.present?
      
      base_query
    end
    
    def build_base_query
      # Get all pool models that have repr_text and training_eligibility
      pool_entities = []
      
      %w[Idea Manifest Experience Relational Evolutionary Practical Emanation].each do |pool_name|
        model_class = pool_name.constantize
        
        # Find entities with repr_text that don't have embeddings yet
        entities_without_embeddings = model_class
          .where.not(repr_text: [nil, ''])
          .where(training_eligible: true) # Only embed training-eligible content
          .where.not(
            id: ::Embedding.where(
              embeddable_type: pool_name,
              embedding_type: 'entity'
            ).select(:embeddable_id)
          )
        
        pool_entities << entities_without_embeddings
      end
      
      # Union all queries (this returns an array, not AR relation)
      # For now, we'll process each pool separately
      pool_entities
    end
    
    def process_batch(entities)
      # Skip if dry run
      if @dry_run
        Rails.logger.info "DRY RUN: Would process #{entities.size} entities"
        @processed_count += entities.size
        return
      end
      
      # Prepare texts for embedding
      texts_to_embed = entities.map(&:repr_text)
      
      # Call OpenAI API to get embeddings
      embeddings = generate_embeddings(texts_to_embed)
      
      return if embeddings.nil?
      
      # Prepare bulk insert data
      embedding_records = []
      
      entities.each_with_index do |entity, index|
        next unless embeddings[index]
        
        embedding_records << {
          embeddable_type: entity.class.name,
          embeddable_id: entity.id,
          pool: entity.class.name.downcase,
          embedding_type: 'entity',
          source_text: entity.repr_text,
          text_hash: Digest::SHA256.hexdigest(entity.repr_text),
          embedding: embeddings[index],
          publishable: entity.publishable,
          training_eligible: entity.training_eligible,
          metadata: {
            canonical_name: entity.canonical_name,
            created_at: entity.created_at
          },
          model_version: ::Embedding::OPENAI_MODEL,
          indexed_at: Time.current,
          created_at: Time.current,
          updated_at: Time.current
        }
      end
      
      # Bulk insert embeddings
      if embedding_records.any?
        ::Embedding.bulk_insert_embeddings(embedding_records)
        @processed_count += embedding_records.size
        Rails.logger.info "Inserted #{embedding_records.size} entity embeddings"
      end
      
    rescue StandardError => e
      Rails.logger.error "Error processing batch: #{e.message}"
      @error_count += entities.size
    end
    
    def generate_embeddings(texts)
      return [] if texts.empty?
      
      retries = 0
      
      begin
        # Call OpenAI embeddings API
        response = OPENAI.embeddings.create(
          input: texts,
          model: ::Embedding::OPENAI_MODEL,
          dimensions: ::Embedding::OPENAI_DIMENSIONS
        )
        
        # Extract embeddings from response
        response.data.map(&:embedding)
        
      rescue StandardError => e
        retries += 1
        if retries < MAX_RETRIES
          Rails.logger.warn "OpenAI API error (attempt #{retries}/#{MAX_RETRIES}): #{e.message}"
          sleep(RETRY_DELAY * retries)
          retry
        else
          Rails.logger.error "OpenAI API failed after #{MAX_RETRIES} attempts: #{e.message}"
          nil
        end
      end
    end
    
    # Process each pool type separately to handle properly
    def call
      Rails.logger.info "Starting entity embedding generation for batch #{batch_id}"
      
      results = {
        processed: 0,
        errors: 0,
        skipped: 0,
        by_pool: {}
      }
      
      # Process each pool type
      %w[Idea Manifest Experience Relational Evolutionary Practical Emanation].each do |pool_name|
        next if @pool_filter.present? && @pool_filter != pool_name.downcase
        
        pool_results = process_pool(pool_name)
        results[:processed] += pool_results[:processed]
        results[:errors] += pool_results[:errors]
        results[:skipped] += pool_results[:skipped]
        results[:by_pool][pool_name.downcase] = pool_results
      end
      
      Rails.logger.info "Entity embedding generation complete: #{results.inspect}"
      results
    end
    
    def process_pool(pool_name)
      model_class = pool_name.constantize
      pool_results = { processed: 0, errors: 0, skipped: 0 }
      
      # Find entities needing embeddings
      entities = model_class
        .where.not(repr_text: [nil, ''])
        .where(training_eligible: true)
        .where.not(
          id: ::Embedding.where(
            embeddable_type: pool_name,
            embedding_type: 'entity'
          ).select(:embeddable_id)
        )
      
      entities = entities.where(ingest_batch_id: @batch_id) if @batch_id.present?
      
      if entities.empty?
        Rails.logger.info "No #{pool_name} entities need embeddings"
        return pool_results
      end
      
      Rails.logger.info "Processing #{entities.count} #{pool_name} entities"
      
      # Process in batches
      entities.find_in_batches(batch_size: BATCH_SIZE) do |batch|
        batch_results = process_entity_batch(batch, pool_name)
        pool_results[:processed] += batch_results[:processed]
        pool_results[:errors] += batch_results[:errors]
      end
      
      pool_results
    end
    
    def process_entity_batch(entities, pool_name)
      return { processed: entities.size, errors: 0 } if @dry_run
      
      texts = entities.map(&:repr_text)
      embeddings = generate_embeddings(texts)
      
      return { processed: 0, errors: entities.size } if embeddings.nil?
      
      embedding_records = entities.zip(embeddings).map do |entity, embedding|
        next unless embedding
        
        {
          embeddable_type: pool_name,
          embeddable_id: entity.id,
          pool: pool_name.downcase,
          embedding_type: 'entity',
          source_text: entity.repr_text,
          text_hash: Digest::SHA256.hexdigest(entity.repr_text),
          embedding: embedding,
          publishable: entity.publishable,
          training_eligible: entity.training_eligible,
          metadata: {
            canonical_name: entity.canonical_name,
            created_at: entity.created_at.iso8601
          },
          model_version: ::Embedding::OPENAI_MODEL,
          indexed_at: Time.current,
          created_at: Time.current,
          updated_at: Time.current
        }
      end.compact
      
      if embedding_records.any?
        ::Embedding.bulk_insert_embeddings(embedding_records)
      end
      
      { processed: embedding_records.size, errors: entities.size - embedding_records.size }
    rescue StandardError => e
      Rails.logger.error "Error in batch: #{e.message}"
      { processed: 0, errors: entities.size }
    end
  end
end