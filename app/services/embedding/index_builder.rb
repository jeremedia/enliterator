module EmbeddingServices
  class IndexBuilder
    include ActiveModel::Model
    
    # Index configuration based on pgvector best practices
    HNSW_CONFIG = {
      m: 16,                    # Connections per layer
      ef_construction: 64,      # Build quality
      ef_search: 100           # Search quality (runtime)
    }.freeze
    
    IVFFLAT_CONFIG = {
      lists: 100,              # Number of clusters
      probes: 10               # Clusters to search
    }.freeze
    
    attr_accessor :index_type, :force_rebuild
    
    def initialize(index_type: 'hnsw', force_rebuild: false)
      @index_type = index_type
      @force_rebuild = force_rebuild
    end
    
    def call
      Rails.logger.info "Building #{@index_type} index for embeddings"
      
      # Check if we need to rebuild
      if index_exists? && !@force_rebuild
        Rails.logger.info "Index already exists. Use force_rebuild: true to rebuild."
        optimize_index
        return { status: 'optimized', index_type: @index_type }
      end
      
      # Drop existing index if forcing rebuild
      drop_existing_index if @force_rebuild
      
      # Build the appropriate index type
      case @index_type
      when 'hnsw'
        build_hnsw_index
      when 'ivfflat'
        build_ivfflat_index
      else
        raise ArgumentError, "Unknown index type: #{@index_type}"
      end
      
      # Optimize query settings
      optimize_index
      
      # Analyze table for query planner
      analyze_table
      
      {
        status: 'built',
        index_type: @index_type,
        config: current_config,
        stats: index_stats
      }
    end
    
    # Performance tuning methods
    def self.optimize_for_search(quality: 'balanced')
      case quality
      when 'fast'
        # Fast but lower recall
        set_hnsw_search_params(ef_search: 40)
        set_ivfflat_search_params(probes: 5)
      when 'balanced'
        # Default balanced settings
        set_hnsw_search_params(ef_search: 100)
        set_ivfflat_search_params(probes: 10)
      when 'accurate'
        # High recall but slower
        set_hnsw_search_params(ef_search: 200)
        set_ivfflat_search_params(probes: 20)
      else
        raise ArgumentError, "Unknown quality setting: #{quality}"
      end
    end
    
    def self.set_hnsw_search_params(ef_search: 100)
      ActiveRecord::Base.connection.execute("SET hnsw.ef_search = #{ef_search}")
      Rails.logger.info "HNSW ef_search set to #{ef_search}"
    end
    
    def self.set_ivfflat_search_params(probes: 10)
      ActiveRecord::Base.connection.execute("SET ivfflat.probes = #{probes}")
      Rails.logger.info "IVFFlat probes set to #{probes}"
    end
    
    # Enable iterative scan for better filtering performance
    def self.enable_iterative_scan
      ActiveRecord::Base.connection.execute("SET hnsw.iterative_scan = relaxed_order")
      Rails.logger.info "HNSW iterative scan enabled"
    end
    
    # Maintenance methods
    def self.reindex_all
      Rails.logger.info "Starting full reindex of embeddings"
      
      # Drop and recreate index
      builder = new(force_rebuild: true)
      builder.call
      
      # Vacuum analyze for optimal performance
      ActiveRecord::Base.connection.execute("VACUUM ANALYZE embeddings")
      
      Rails.logger.info "Reindex complete"
    end
    
    def self.update_statistics
      ActiveRecord::Base.connection.execute("ANALYZE embeddings")
      Rails.logger.info "Table statistics updated"
    end
    
    private
    
    def index_exists?
      result = ActiveRecord::Base.connection.execute(<<~SQL)
        SELECT indexname 
        FROM pg_indexes 
        WHERE tablename = 'embeddings' 
        AND indexname LIKE '%embedding%'
        AND indexdef LIKE '%USING #{@index_type}%'
      SQL
      
      result.any?
    end
    
    def drop_existing_index
      Rails.logger.info "Dropping existing vector index"
      
      # Find all vector indexes
      indexes = ActiveRecord::Base.connection.execute(<<~SQL)
        SELECT indexname 
        FROM pg_indexes 
        WHERE tablename = 'embeddings' 
        AND indexname LIKE '%embedding%'
        AND (indexdef LIKE '%USING hnsw%' OR indexdef LIKE '%USING ivfflat%')
      SQL
      
      indexes.each do |row|
        ActiveRecord::Base.connection.execute("DROP INDEX IF EXISTS #{row['indexname']}")
        Rails.logger.info "Dropped index: #{row['indexname']}"
      end
    end
    
    def build_hnsw_index
      Rails.logger.info "Building HNSW index with config: #{HNSW_CONFIG}"
      
      # Set build parameters for optimal index creation
      ActiveRecord::Base.connection.execute("SET maintenance_work_mem = '2GB'")
      ActiveRecord::Base.connection.execute("SET max_parallel_maintenance_workers = 7")
      
      # Create HNSW index with cosine distance
      ActiveRecord::Base.connection.execute(<<~SQL)
        CREATE INDEX IF NOT EXISTS embeddings_hnsw_idx 
        ON embeddings 
        USING hnsw (embedding vector_cosine_ops)
        WITH (m = #{HNSW_CONFIG[:m]}, ef_construction = #{HNSW_CONFIG[:ef_construction]})
      SQL
      
      # Reset to defaults
      ActiveRecord::Base.connection.execute("RESET maintenance_work_mem")
      ActiveRecord::Base.connection.execute("RESET max_parallel_maintenance_workers")
      
      Rails.logger.info "HNSW index created successfully"
    end
    
    def build_ivfflat_index
      Rails.logger.info "Building IVFFlat index with config: #{IVFFLAT_CONFIG}"
      
      # IVFFlat requires training on sample data
      sample_size = [::Embedding.count, 10000].min
      
      if sample_size < 100
        Rails.logger.warn "Not enough embeddings for IVFFlat (need at least 100)"
        return
      end
      
      # Set build parameters
      ActiveRecord::Base.connection.execute("SET maintenance_work_mem = '2GB'")
      ActiveRecord::Base.connection.execute("SET max_parallel_maintenance_workers = 7")
      
      # Create IVFFlat index
      ActiveRecord::Base.connection.execute(<<~SQL)
        CREATE INDEX IF NOT EXISTS embeddings_ivfflat_idx 
        ON embeddings 
        USING ivfflat (embedding vector_cosine_ops)
        WITH (lists = #{IVFFLAT_CONFIG[:lists]})
      SQL
      
      # Reset to defaults
      ActiveRecord::Base.connection.execute("RESET maintenance_work_mem")
      ActiveRecord::Base.connection.execute("RESET max_parallel_maintenance_workers")
      
      Rails.logger.info "IVFFlat index created successfully"
    end
    
    def optimize_index
      case @index_type
      when 'hnsw'
        self.class.set_hnsw_search_params(ef_search: HNSW_CONFIG[:ef_search])
        self.class.enable_iterative_scan
      when 'ivfflat'
        self.class.set_ivfflat_search_params(probes: IVFFLAT_CONFIG[:probes])
      end
    end
    
    def analyze_table
      ActiveRecord::Base.connection.execute("ANALYZE embeddings")
      Rails.logger.info "Table analyzed for query optimization"
    end
    
    def current_config
      case @index_type
      when 'hnsw'
        HNSW_CONFIG
      when 'ivfflat'
        IVFFLAT_CONFIG
      else
        {}
      end
    end
    
    def index_stats
      stats = {}
      
      # Get index size
      result = ActiveRecord::Base.connection.execute(<<~SQL)
        SELECT 
          pg_size_pretty(pg_relation_size(indexname::regclass)) as size
        FROM pg_indexes 
        WHERE tablename = 'embeddings' 
        AND indexname LIKE '%#{@index_type}%'
        LIMIT 1
      SQL
      
      stats[:index_size] = result.first['size'] if result.any?
      
      # Get table stats
      stats[:total_embeddings] = ::Embedding.count
      stats[:entity_embeddings] = ::Embedding.entities.count
      stats[:path_embeddings] = ::Embedding.paths.count
      stats[:publishable] = ::Embedding.publishable.count
      stats[:training_eligible] = ::Embedding.training_eligible.count
      
      stats
    end
  end
end