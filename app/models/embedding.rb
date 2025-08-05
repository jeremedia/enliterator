class Embedding < ApplicationRecord
  # Neighbor gem configuration for vector similarity search
  # normalize: true converts vectors to unit vectors for cosine similarity
  # dimensions: 1536 for OpenAI text-embedding-3-small model
  has_neighbors :embedding, dimensions: 1536, normalize: true
  
  # Constants
  OPENAI_MODEL = 'text-embedding-3-small'.freeze
  OPENAI_DIMENSIONS = 1536
  BATCH_SIZE = 100 # OpenAI recommends batching for efficiency
  MAX_TOKENS = 8191 # Model limit
  
  EMBEDDING_TYPES = %w[entity path].freeze
  POOLS = %w[idea manifest experience relational evolutionary practical emanation].freeze
  
  # Validations
  validates :embeddable_type, :embeddable_id, :pool, :embedding_type, presence: true
  validates :source_text, :text_hash, presence: true
  validates :embedding_type, inclusion: { in: EMBEDDING_TYPES }
  validates :pool, inclusion: { in: POOLS }
  validates :text_hash, uniqueness: true
  validates :embedding, presence: true
  
  # Scopes for rights-aware filtering
  scope :publishable, -> { where(publishable: true) }
  scope :training_eligible, -> { where(training_eligible: true) }
  scope :rights_filtered, ->(require_rights = 'public') {
    case require_rights
    when 'public'
      publishable
    when 'internal'
      training_eligible
    else
      all
    end
  }
  
  # Scopes for filtering by type
  scope :entities, -> { where(embedding_type: 'entity') }
  scope :paths, -> { where(embedding_type: 'path') }
  scope :by_pool, ->(pool) { where(pool: pool) if pool.present? }
  scope :indexed, -> { where.not(indexed_at: nil) }
  
  # Search methods using neighbor gem
  def self.semantic_search(query_embedding, options = {})
    top_k = options[:top_k] || 10
    require_rights = options[:require_rights] || 'public'
    pools = options[:pools] || []
    
    # Start with base query
    query = rights_filtered(require_rights)
    
    # Apply pool filters if specified
    if pools.any?
      query = query.where(pool: pools)
    end
    
    # Use neighbor's nearest_neighbors with cosine distance
    # Since we normalize vectors, cosine and inner_product are equivalent
    query.nearest_neighbors(:embedding, query_embedding, distance: 'cosine')
         .limit(top_k)
  end
  
  # Find similar items to this embedding
  def find_similar(limit: 10, require_rights: 'public')
    self.class
        .rights_filtered(require_rights)
        .where.not(id: id)
        .nearest_neighbors(:embedding, embedding, distance: 'cosine')
        .limit(limit)
  end
  
  # Set query-time parameters for HNSW index
  def self.set_search_quality(ef_search: 100)
    connection.execute("SET hnsw.ef_search = #{ef_search}")
  end
  
  # Enable iterative scan for better filtering performance
  def self.enable_iterative_scan
    connection.execute("SET hnsw.iterative_scan = relaxed_order")
  end
  
  # Callbacks
  before_validation :compute_text_hash
  before_save :set_model_version
  
  # Bulk insert method for efficiency
  def self.bulk_insert_embeddings(embeddings_data)
    # Ensure all vectors are normalized if using cosine similarity
    embeddings_data.each do |data|
      if data[:embedding].is_a?(Array)
        magnitude = Math.sqrt(data[:embedding].sum { |x| x**2 })
        data[:embedding] = data[:embedding].map { |x| x / magnitude } if magnitude > 0
      end
    end
    
    # Use insert_all! for efficient bulk insertion
    insert_all!(embeddings_data, unique_by: :text_hash)
  end
  
  # Get coverage statistics
  def self.coverage_stats
    {
      total: count,
      by_pool: group(:pool).count,
      by_type: group(:embedding_type).count,
      publishable: publishable.count,
      training_eligible: training_eligible.count,
      indexed: indexed.count
    }
  end
  
  private
  
  def compute_text_hash
    self.text_hash = Digest::SHA256.hexdigest(source_text) if source_text.present?
  end
  
  def set_model_version
    self.model_version ||= OPENAI_MODEL
  end
end