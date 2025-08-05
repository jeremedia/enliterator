module Embedding
  class BatchProcessor
    include ActiveModel::Model
    
    # Batch API configuration
    MAX_REQUESTS_PER_BATCH = 50000  # OpenAI limit
    MAX_FILE_SIZE_MB = 200          # OpenAI limit
    COMPLETION_WINDOW = '24h'
    
    attr_accessor :batch_id, :ingest_batch_id, :dry_run
    attr_reader :stats
    
    def initialize(ingest_batch_id:, dry_run: false)
      @ingest_batch_id = ingest_batch_id
      @dry_run = dry_run
      @stats = {
        entities_queued: 0,
        paths_queued: 0,
        batches_created: [],
        total_cost_savings: 0
      }
    end
    
    # Main entry point - prepares and submits all embedding requests
    def process
      Rails.logger.info "Starting Batch API processing for ingest batch #{@ingest_batch_id}"
      
      # Collect all items needing embeddings
      entity_requests = prepare_entity_requests
      path_requests = prepare_path_requests
      
      all_requests = entity_requests + path_requests
      
      if all_requests.empty?
        Rails.logger.info "No items need embeddings"
        return @stats
      end
      
      Rails.logger.info "Preparing #{all_requests.size} embedding requests"
      
      # Split into batches if needed (50k request limit)
      all_requests.each_slice(MAX_REQUESTS_PER_BATCH) do |batch_requests|
        batch_id = submit_batch(batch_requests)
        @stats[:batches_created] << batch_id if batch_id
      end
      
      # Calculate estimated cost savings (50% off)
      estimate_savings(all_requests.size)
      
      # Store batch IDs for tracking
      store_batch_metadata if @stats[:batches_created].any?
      
      Rails.logger.info "Batch API processing initiated: #{@stats.inspect}"
      @stats
    end
    
    # Check status of submitted batches
    def check_status(batch_ids = nil)
      batch_ids ||= get_stored_batch_ids
      
      statuses = {}
      batch_ids.each do |batch_id|
        begin
          batch = OPENAI.batches.retrieve(batch_id)
          statuses[batch_id] = {
            status: batch.status,
            completed: batch.request_counts['completed'],
            failed: batch.request_counts['failed'],
            total: batch.request_counts['total'],
            created_at: batch.created_at,
            expires_at: batch.expires_at
          }
        rescue => e
          Rails.logger.error "Error checking batch #{batch_id}: #{e.message}"
          statuses[batch_id] = { error: e.message }
        end
      end
      
      statuses
    end
    
    # Process completed batch results
    def process_results(batch_id)
      Rails.logger.info "Processing results for batch #{batch_id}"
      
      batch = OPENAI.batches.retrieve(batch_id)
      
      unless batch.status == 'completed'
        Rails.logger.warn "Batch #{batch_id} not complete: #{batch.status}"
        return { status: batch.status, processed: 0 }
      end
      
      # Download output file
      output = download_batch_output(batch.output_file_id)
      error_output = download_batch_output(batch.error_file_id) if batch.error_file_id
      
      # Process successful results
      processed_count = process_output_file(output)
      
      # Process errors if any
      if error_output
        process_error_file(error_output)
      end
      
      { 
        status: 'processed',
        processed: processed_count,
        failed: batch.request_counts['failed']
      }
    end
    
    private
    
    def prepare_entity_requests
      requests = []
      
      %w[Idea Manifest Experience Relational Evolutionary Practical Emanation].each do |pool_name|
        model_class = pool_name.constantize
        
        # Find entities needing embeddings
        entities = model_class
          .where(ingest_batch_id: @ingest_batch_id)
          .where.not(repr_text: [nil, ''])
          .where(training_eligible: true)
          .where.not(
            id: ::Embedding.where(
              embeddable_type: pool_name,
              embedding_type: 'entity'
            ).select(:embeddable_id)
          )
        
        entities.find_each do |entity|
          requests << build_embedding_request(
            custom_id: "entity-#{pool_name}-#{entity.id}",
            text: entity.repr_text,
            metadata: {
              type: 'entity',
              pool: pool_name.downcase,
              entity_id: entity.id,
              publishable: entity.publishable,
              training_eligible: entity.training_eligible
            }
          )
        end
        
        @stats[:entities_queued] += entities.count
      end
      
      requests
    end
    
    def prepare_path_requests
      requests = []
      
      # Sample paths from Neo4j for this batch
      paths = sample_batch_paths
      
      paths.each_with_index do |path_data, index|
        path_text = textize_path(path_data)
        path_hash = compute_path_hash(path_data)
        
        # Skip if already embedded
        next if ::Embedding.exists?(text_hash: path_hash)
        
        requests << build_embedding_request(
          custom_id: "path-#{path_hash}",
          text: path_text,
          metadata: {
            type: 'path',
            path_hash: path_hash,
            node_ids: path_data[:nodes].map { |n| n[:id] },
            pools: path_data[:nodes].map { |n| n[:pool] }.uniq,
            publishable: path_data[:nodes].all? { |n| n[:publishable] },
            training_eligible: path_data[:nodes].all? { |n| n[:training_eligible] }
          }
        )
        
        @stats[:paths_queued] += 1
      end
      
      requests
    end
    
    def build_embedding_request(custom_id:, text:, metadata:)
      {
        custom_id: custom_id,
        method: "POST",
        url: "/v1/embeddings",
        body: {
          input: text,
          model: ::Embedding::OPENAI_MODEL,
          dimensions: ::Embedding::OPENAI_DIMENSIONS
        },
        metadata: metadata  # Store for processing results
      }
    end
    
    def submit_batch(requests)
      return nil if @dry_run
      
      # Create JSONL file
      file_path = Rails.root.join('tmp', "batch_#{Time.current.to_i}.jsonl")
      
      File.open(file_path, 'w') do |f|
        requests.each do |request|
          # Extract metadata before writing (not part of OpenAI request)
          metadata = request.delete(:metadata)
          f.puts request.to_json
          
          # Store metadata separately for later processing
          store_request_metadata(request[:custom_id], metadata)
        end
      end
      
      begin
        # Upload file to OpenAI
        Rails.logger.info "Uploading batch file: #{file_path}"
        file = OPENAI.files.create(
          file: File.open(file_path, 'rb'),
          purpose: 'batch'
        )
        
        # Create batch
        Rails.logger.info "Creating batch with file ID: #{file.id}"
        batch = OPENAI.batches.create(
          input_file_id: file.id,
          endpoint: '/v1/embeddings',
          completion_window: COMPLETION_WINDOW,
          metadata: {
            ingest_batch_id: @ingest_batch_id,
            created_by: 'BatchProcessor'
          }
        )
        
        Rails.logger.info "Batch created: #{batch.id}"
        batch.id
        
      ensure
        # Clean up temp file
        File.delete(file_path) if File.exist?(file_path)
      end
    end
    
    def download_batch_output(file_id)
      return nil unless file_id
      
      Rails.logger.info "Downloading file: #{file_id}"
      response = OPENAI.files.content(file_id)
      
      # Parse JSONL response
      response.text.split("\n").map do |line|
        next if line.strip.empty?
        JSON.parse(line)
      end.compact
    end
    
    def process_output_file(output_lines)
      embedding_records = []
      
      output_lines.each do |line|
        next unless line['response'] && line['response']['status_code'] == 200
        
        custom_id = line['custom_id']
        embedding_data = line['response']['body']['data'].first
        embedding_vector = embedding_data['embedding']
        
        # Retrieve stored metadata
        metadata = get_request_metadata(custom_id)
        next unless metadata
        
        # Build embedding record based on type
        if metadata['type'] == 'entity'
          embedding_records << build_entity_embedding_record(
            custom_id, embedding_vector, metadata
          )
        elsif metadata['type'] == 'path'
          embedding_records << build_path_embedding_record(
            custom_id, embedding_vector, metadata
          )
        end
      end
      
      # Bulk insert all embeddings
      if embedding_records.any?
        ::Embedding.bulk_insert_embeddings(embedding_records)
        Rails.logger.info "Inserted #{embedding_records.size} embeddings from batch"
      end
      
      embedding_records.size
    end
    
    def build_entity_embedding_record(custom_id, embedding, metadata)
      entity_class = metadata['pool'].capitalize.constantize
      entity = entity_class.find(metadata['entity_id'])
      
      {
        embeddable_type: entity_class.name,
        embeddable_id: entity.id,
        pool: metadata['pool'],
        embedding_type: 'entity',
        source_text: entity.repr_text,
        text_hash: Digest::SHA256.hexdigest(entity.repr_text),
        embedding: embedding,
        publishable: metadata['publishable'],
        training_eligible: metadata['training_eligible'],
        metadata: {
          canonical_name: entity.canonical_name,
          batch_api: true,
          batch_id: @batch_id
        },
        model_version: ::Embedding::OPENAI_MODEL,
        indexed_at: Time.current,
        created_at: Time.current,
        updated_at: Time.current
      }
    end
    
    def build_path_embedding_record(custom_id, embedding, metadata)
      {
        embeddable_type: 'Path',
        embeddable_id: metadata['path_hash'],
        pool: metadata['pools'].first, # Primary pool
        embedding_type: 'path',
        source_text: '[Path text stored separately]', # Reconstruct if needed
        text_hash: metadata['path_hash'],
        embedding: embedding,
        publishable: metadata['publishable'],
        training_eligible: metadata['training_eligible'],
        metadata: {
          node_ids: metadata['node_ids'],
          pools_involved: metadata['pools'],
          batch_api: true,
          batch_id: @batch_id
        },
        model_version: ::Embedding::OPENAI_MODEL,
        indexed_at: Time.current,
        created_at: Time.current,
        updated_at: Time.current
      }
    end
    
    def process_error_file(error_lines)
      error_lines.each do |line|
        custom_id = line['custom_id']
        error = line['error']
        
        Rails.logger.error "Batch API error for #{custom_id}: #{error['code']} - #{error['message']}"
        
        # Could store failed items for retry with synchronous API
      end
    end
    
    def sample_batch_paths
      # Implementation would query Neo4j for paths related to this batch
      # Simplified for now
      []
    end
    
    def textize_path(path_data)
      # Reuse existing PathTextizer logic
      "Path: " + path_data[:nodes].map { |n| "#{n[:pool].capitalize}(#{n[:canonical_name]})" }.join(' → ')
    end
    
    def compute_path_hash(path_data)
      path_string = path_data[:nodes].map { |n| "#{n[:pool]}:#{n[:id]}" }.join('->')
      Digest::SHA256.hexdigest(path_string)
    end
    
    def store_request_metadata(custom_id, metadata)
      # Store in Redis or database for later retrieval
      Rails.cache.write(
        "batch_metadata:#{custom_id}",
        metadata,
        expires_in: 48.hours
      )
    end
    
    def get_request_metadata(custom_id)
      Rails.cache.read("batch_metadata:#{custom_id}")
    end
    
    def store_batch_metadata
      # Store batch IDs for this ingest batch
      Rails.cache.write(
        "ingest_batch:#{@ingest_batch_id}:batch_ids",
        @stats[:batches_created],
        expires_in: 7.days
      )
    end
    
    def get_stored_batch_ids
      Rails.cache.read("ingest_batch:#{@ingest_batch_id}:batch_ids") || []
    end
    
    def estimate_savings(request_count)
      # Rough estimate: 0.02 cents per 1K tokens, assume 10 tokens per request
      estimated_tokens = request_count * 10
      standard_cost = (estimated_tokens / 1000.0) * 0.00002  # $0.020 per 1M tokens
      batch_cost = standard_cost * 0.5  # 50% discount
      @stats[:total_cost_savings] = (standard_cost - batch_cost).round(4)
    end
  end
end