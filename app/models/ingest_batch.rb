# frozen_string_literal: true

# Represents a batch of items being processed through the pipeline
class IngestBatch < ApplicationRecord
  has_many :ingest_items, dependent: :destroy
  
  # Status tracking for pipeline stages
  enum :status, {
    pending: 0,
    intake_in_progress: 1,
    intake_completed: 2,
    intake_failed: 3,
    triage_in_progress: 4,
    triage_completed: 5,
    triage_needs_review: 6,
    triage_failed: 7,
    lexicon_in_progress: 8,
    lexicon_completed: 9,
    pool_filling_in_progress: 10,
    pool_filling_completed: 11,
    graph_assembly_in_progress: 12,
    graph_assembly_completed: 13,
    representations_in_progress: 14,
    representations_completed: 15,
    scoring_in_progress: 16,
    scoring_completed: 17,
    deliverables_in_progress: 18,
    completed: 19,
    failed: 20
  }, prefix: true
  
  # Validations
  validates :name, presence: true
  validates :source_type, presence: true
  
  # Scopes
  scope :recent, -> { order(created_at: :desc) }
  scope :completed, -> { where(status: :completed) }
  scope :failed, -> { where(status: [:intake_failed, :triage_failed, :failed]) }
  scope :needs_review, -> { where(status: :triage_needs_review) }
  
  # Callbacks
  before_validation :set_defaults
  
  # Data Isolation Methods
  # Each EKN gets completely isolated resources
  
  def neo4j_database_name
    # Sanitized database name for Neo4j (only simple ascii, numbers, dots, dashes)
    "ekn-#{id}"
  end
  
  def postgres_schema_name
    # Schema name for PostgreSQL isolation
    "ekn_#{id}"
  end
  
  def storage_root_path
    # Root path for file storage
    case ENV.fetch('STORAGE_TYPE', 'filesystem')
    when 'filesystem'
      Rails.root.join('storage', 'ekns', id.to_s)
    when 's3'
      "s3://#{ENV['S3_BUCKET']}/ekns/#{id}/"
    else
      Rails.root.join('storage', 'ekns', id.to_s)
    end
  end
  
  def ensure_neo4j_database_exists!
    Graph::DatabaseManager.ensure_database_exists(neo4j_database_name)
  end
  
  def drop_neo4j_database!
    Graph::DatabaseManager.drop_database(neo4j_database_name)
  end
  
  def ensure_postgres_schema_exists!
    ApplicationRecord.connection.execute(<<-SQL)
      CREATE SCHEMA IF NOT EXISTS #{postgres_schema_name};
      
      -- Create isolated embeddings table with pgvector
      CREATE TABLE IF NOT EXISTS #{postgres_schema_name}.embeddings (
        id BIGSERIAL PRIMARY KEY,
        entity_id VARCHAR NOT NULL,
        entity_type VARCHAR NOT NULL,
        content TEXT,
        embedding vector(1536),
        metadata JSONB DEFAULT '{}',
        created_at TIMESTAMP DEFAULT NOW(),
        updated_at TIMESTAMP DEFAULT NOW()
      );
      
      -- Create HNSW index for similarity search
      CREATE INDEX IF NOT EXISTS idx_#{postgres_schema_name}_embeddings_hnsw 
      ON #{postgres_schema_name}.embeddings 
      USING hnsw (embedding vector_cosine_ops);
      
      -- Create documents table
      CREATE TABLE IF NOT EXISTS #{postgres_schema_name}.documents (
        id BIGSERIAL PRIMARY KEY,
        path VARCHAR NOT NULL,
        content TEXT,
        mime_type VARCHAR,
        size_bytes BIGINT,
        hash VARCHAR,
        metadata JSONB DEFAULT '{}',
        created_at TIMESTAMP DEFAULT NOW()
      );
      
      -- Create entities table
      CREATE TABLE IF NOT EXISTS #{postgres_schema_name}.entities (
        id BIGSERIAL PRIMARY KEY,
        neo4j_id VARCHAR,
        name VARCHAR NOT NULL,
        canonical_name VARCHAR,
        pool VARCHAR,
        surface_forms TEXT[],
        created_at TIMESTAMP DEFAULT NOW()
      );
      
      -- Create lexicon table
      CREATE TABLE IF NOT EXISTS #{postgres_schema_name}.lexicon_entries (
        id BIGSERIAL PRIMARY KEY,
        canonical_name VARCHAR NOT NULL,
        surface_forms TEXT[],
        negative_forms TEXT[],
        description TEXT,
        pool VARCHAR,
        created_at TIMESTAMP DEFAULT NOW()
      );
    SQL
    
    Rails.logger.info "Ensured PostgreSQL schema exists: #{postgres_schema_name}"
  rescue => e
    Rails.logger.error "Failed to create PostgreSQL schema: #{e.message}"
    raise
  end
  
  def drop_postgres_schema!
    ApplicationRecord.connection.execute(<<-SQL)
      DROP SCHEMA IF EXISTS #{postgres_schema_name} CASCADE;
    SQL
    Rails.logger.info "Dropped PostgreSQL schema: #{postgres_schema_name}"
  end
  
  def ensure_storage_exists!
    return unless ENV.fetch('STORAGE_TYPE', 'filesystem') == 'filesystem'
    
    path = storage_root_path
    FileUtils.mkdir_p(path)
    FileUtils.mkdir_p(path.join('uploads'))
    FileUtils.mkdir_p(path.join('processed'))
    FileUtils.mkdir_p(path.join('exports'))
    
    Rails.logger.info "Ensured storage directories exist: #{path}"
  end
  
  def drop_all_storage!
    return unless ENV.fetch('STORAGE_TYPE', 'filesystem') == 'filesystem'
    
    path = storage_root_path
    if path.to_s.include?('/ekns/') # Safety check
      FileUtils.rm_rf(path)
      Rails.logger.info "Removed storage directory: #{path}"
    end
  end
  
  def ensure_all_resources_exist!
    # Create all isolated resources for this EKN
    ensure_neo4j_database_exists!
    ensure_postgres_schema_exists!
    ensure_storage_exists!
    Rails.logger.info "All resources created for EKN #{id}: #{name}"
  end
  
  def destroy_all_resources!
    # Destroy all isolated resources for this EKN
    drop_neo4j_database!
    drop_postgres_schema!
    drop_all_storage!
    Rails.logger.info "All resources destroyed for EKN #{id}: #{name}"
  end
  
  def progress_percentage
    return 0 if status_pending?
    return 100 if status_completed?
    
    # Map status to rough percentage
    status_mapping = {
      intake_in_progress: 5,
      intake_completed: 10,
      triage_in_progress: 15,
      triage_completed: 20,
      lexicon_in_progress: 30,
      lexicon_completed: 35,
      pool_filling_in_progress: 45,
      pool_filling_completed: 50,
      graph_assembly_in_progress: 60,
      graph_assembly_completed: 65,
      representations_in_progress: 75,
      representations_completed: 80,
      scoring_in_progress: 85,
      scoring_completed: 90,
      deliverables_in_progress: 95
    }
    
    status_mapping[status.to_sym] || 0
  end
  
  def items_by_status
    ingest_items.group(:triage_status).count
  end
  
  def restart_pipeline!
    update!(status: :pending)
    ingest_items.update_all(triage_status: 'pending')
    Pipeline::IntakeJob.perform_later(id)
  end
  
  private
  
  def set_defaults
    self.metadata ||= {}
    self.statistics ||= {}
  end
end