module Embedding
  class PathEmbedder
    include ActiveModel::Model
    
    # Configuration
    BATCH_SIZE = 50 # Smaller batch for paths as they're longer
    MAX_PATH_LENGTH = 5 # Maximum hops in a path
    MIN_PATH_LENGTH = 2 # Minimum hops for interesting paths
    PATHS_PER_NODE = 10 # Sample paths per starting node
    MAX_RETRIES = 3
    RETRY_DELAY = 2
    
    attr_accessor :batch_id, :pool_filter, :dry_run, :max_paths
    
    def initialize(batch_id: nil, pool_filter: nil, dry_run: false, max_paths: 1000)
      @batch_id = batch_id
      @pool_filter = pool_filter
      @dry_run = dry_run
      @max_paths = max_paths
      @processed_count = 0
      @error_count = 0
      @neo4j = Neo4j::Driver::GraphDatabase.driver(
        ENV.fetch('NEO4J_URL'),
        Neo4j::Driver::AuthTokens.basic(
          ENV.fetch('NEO4J_USERNAME', 'neo4j'),
          ENV.fetch('NEO4J_PASSWORD')
        )
      )
    end
    
    def call
      Rails.logger.info "Starting path embedding generation"
      
      # Sample paths from the graph
      paths = sample_graph_paths
      
      if paths.empty?
        Rails.logger.info "No paths found to embed"
        return { processed: 0, errors: 0, path_count: 0 }
      end
      
      Rails.logger.info "Found #{paths.size} paths to embed"
      
      # Process paths in batches
      paths.each_slice(BATCH_SIZE) do |batch|
        process_batch(batch)
      end
      
      {
        processed: @processed_count,
        errors: @error_count,
        path_count: paths.size
      }
    ensure
      @neo4j&.close
    end
    
    private
    
    def sample_graph_paths
      paths = []
      
      @neo4j.session do |session|
        # Build the query based on filters
        query = build_path_query
        
        result = session.run(query, pool: @pool_filter)
        
        result.each do |record|
          path = record[:p]
          
          # Convert Neo4j path to our format
          path_data = extract_path_data(path)
          
          # Skip if we've already embedded this path
          path_hash = compute_path_hash(path_data)
          next if ::Embedding.exists?(text_hash: path_hash)
          
          paths << path_data
          
          break if paths.size >= @max_paths
        end
      end
      
      paths
    rescue StandardError => e
      Rails.logger.error "Error sampling paths: #{e.message}"
      []
    end
    
    def build_path_query
      pool_filter = @pool_filter ? "WHERE labels(n)[0] = $pool" : ""
      
      # Sample diverse paths through the graph
      # This query finds paths of varying lengths starting from different node types
      <<~CYPHER
        MATCH (n)
        #{pool_filter}
        WITH n
        ORDER BY rand()
        LIMIT 100
        MATCH p = (n)-[*#{MIN_PATH_LENGTH}..#{MAX_PATH_LENGTH}]->()
        WHERE ALL(node IN nodes(p) WHERE node.training_eligible = true)
        WITH p, rand() as r
        ORDER BY r
        LIMIT #{@max_paths}
        RETURN p
      CYPHER
    end
    
    def extract_path_data(neo4j_path)
      nodes = []
      relationships = []
      
      # Extract nodes
      neo4j_path.nodes.each do |node|
        nodes << {
          id: node[:id],
          canonical_name: node[:canonical_name],
          pool: node.labels.first.downcase,
          publishable: node[:publishable] || false,
          training_eligible: node[:training_eligible] || false
        }
      end
      
      # Extract relationships
      neo4j_path.relationships.each do |rel|
        relationships << {
          type: rel.type,
          start_id: rel.start_node_element_id,
          end_id: rel.end_node_element_id
        }
      end
      
      {
        nodes: nodes,
        relationships: relationships,
        length: neo4j_path.nodes.size
      }
    end
    
    def compute_path_hash(path_data)
      # Create a deterministic hash for the path
      path_string = path_data[:nodes].map { |n| "#{n[:pool]}:#{n[:id]}" }.join('->')
      path_string += '-' + path_data[:relationships].map { |r| r[:type] }.join('-')
      Digest::SHA256.hexdigest(path_string)
    end
    
    def process_batch(paths)
      if @dry_run
        Rails.logger.info "DRY RUN: Would process #{paths.size} paths"
        @processed_count += paths.size
        return
      end
      
      # Convert paths to text using PathTextizer
      path_texts = paths.map { |path_data| textize_path(path_data) }
      
      # Generate embeddings
      embeddings = generate_embeddings(path_texts)
      
      return if embeddings.nil?
      
      # Prepare bulk insert data
      embedding_records = []
      
      paths.each_with_index do |path_data, index|
        next unless embeddings[index]
        
        # Determine rights based on all nodes in path
        publishable = path_data[:nodes].all? { |n| n[:publishable] }
        training_eligible = path_data[:nodes].all? { |n| n[:training_eligible] }
        
        # Get primary pool (most common in path)
        pool_counts = path_data[:nodes].group_by { |n| n[:pool] }
                                       .transform_values(&:count)
        primary_pool = pool_counts.max_by { |_, count| count }[0]
        
        embedding_records << {
          embeddable_type: 'Path',
          embeddable_id: compute_path_hash(path_data),
          pool: primary_pool,
          embedding_type: 'path',
          source_text: path_texts[index],
          text_hash: compute_path_hash(path_data),
          embedding: embeddings[index],
          publishable: publishable,
          training_eligible: training_eligible,
          metadata: {
            node_ids: path_data[:nodes].map { |n| n[:id] },
            pools_involved: path_data[:nodes].map { |n| n[:pool] }.uniq,
            relationship_types: path_data[:relationships].map { |r| r[:type] },
            path_length: path_data[:length]
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
        Rails.logger.info "Inserted #{embedding_records.size} path embeddings"
      end
      
    rescue StandardError => e
      Rails.logger.error "Error processing path batch: #{e.message}"
      @error_count += paths.size
    end
    
    def textize_path(path_data)
      # Use the PathTextizer service to convert path to text
      textizer = Graph::PathTextizer.new(
        nodes: path_data[:nodes],
        relationships: path_data[:relationships]
      )
      
      textizer.to_sentence
    rescue StandardError => e
      Rails.logger.warn "Could not textize path: #{e.message}"
      
      # Fallback to simple format
      path_text = path_data[:nodes].map { |n| "#{n[:pool].capitalize}(#{n[:canonical_name]})" }
                                   .zip(path_data[:relationships].map { |r| r[:type] })
                                   .flatten.compact.join(' → ')
      path_text + "."
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
  end
end