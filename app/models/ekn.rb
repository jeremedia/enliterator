# app/models/ekn.rb
# EKN (Enliterated Knowledge Navigator) - The persistent, growing knowledge domain
# This is the TOP-LEVEL entity that owns IngestBatches, not the other way around!
class Ekn < ApplicationRecord
  extend FriendlyId
  friendly_id :name, use: [:slugged, :finders, :history]
  
  # :slugged - generates URL-safe slugs
  # :finders - allows Ekn.find() to work with slugs OR ids
  # :history - tracks slug changes if you rename an EKN
  
  # Associations - EKN owns everything
  has_many :ingest_batches, dependent: :destroy
  has_many :conversations, dependent: :destroy
  has_many :ingest_items, through: :ingest_batches
  belongs_to :session, optional: true  # For pre-auth ownership
  
  # Core identity validation
  validates :name, presence: true
  validates :status, inclusion: { in: %w[initializing active archived failed] }
  
  # Status management
  enum :status, {
    initializing: 'initializing',
    active: 'active',
    archived: 'archived',
    failed: 'failed'
  }
  
  # Domain types affect how knowledge is processed
  enum :domain_type, {
    general: 'general',
    research: 'research',
    technical: 'technical',
    creative: 'creative',
    personal: 'personal'
  }
  
  # Personality affects response style
  enum :personality, {
    professional: 'professional',
    friendly: 'friendly',
    academic: 'academic',
    casual: 'casual',
    helpful_guide: 'helpful_guide'  # Special for Meta-Enliterator
  }
  
  # CRITICAL: Resource naming - SAME database for all batches!
  def neo4j_database_name
    "ekn-#{id}"  # This NEVER changes for an EKN (dash for Neo4j)
  end
  
  def postgres_schema_name
    "ekn_#{id}"  # PostgreSQL schema for metadata (underscore for PostgreSQL)
  end
  
  def storage_root_path
    Rails.root.join('storage', 'ekns', id.to_s)
  end
  
  # The CRITICAL method - adds knowledge to EXISTING graph
  def add_knowledge(files:, source_type: 'upload')
    # Create new batch UNDER this EKN
    batch = ingest_batches.create!(
      name: "Batch #{ingest_batches.count + 1} for #{name}",
      source_type: source_type,
      status: 'pending',
      metadata: {
        ekn_database: neo4j_database_name,
        batch_number: ingest_batches.count + 1,
        adds_to_existing: true  # Flag that this ADDS to existing knowledge
      }
    )
    
    # Add files to batch
    Array(files).each do |file_path|
      batch.ingest_items.create!(
        file_path: file_path,
        triage_status: 'pending',
        media_type: 'text'  # Default to text for now
      )
    end
    
    # Process the batch INTO THE EXISTING GRAPH
    Rails.logger.info "Adding knowledge to EKN #{id}: #{files.count} files"
    Rails.logger.info "Using database: #{neo4j_database_name}"
    Rails.logger.info "Current nodes before: #{total_nodes}"
    
    # Start the pipeline - it will ADD to existing graph, not replace!
    Pipeline::IntakeJob.perform_later(batch.id)
    
    # For now, return the batch immediately
    # In production, this would be async and we'd check status
    Rails.logger.info "Pipeline started for batch #{batch.id}"
    
    batch
  end
  
  # Query the accumulated knowledge
  def total_nodes
    return 0 unless neo4j_database_exists?
    
    # Use get_statistics which actually exists
    stats = Graph::QueryService.new(neo4j_database_name).get_statistics
    stats[:total_nodes] || 0
  rescue => e
    Rails.logger.error "Error counting nodes for EKN #{id}: #{e.message}"
    0
  end
  
  def total_relationships
    return 0 unless neo4j_database_exists?
    
    # Use get_statistics which actually exists
    stats = Graph::QueryService.new(neo4j_database_name).get_statistics
    stats[:total_relationships] || 0
  rescue => e
    Rails.logger.error "Error counting relationships for EKN #{id}: #{e.message}"
    0
  end
  
  def knowledge_density
    return 0 if total_nodes.zero?
    (total_relationships.to_f / total_nodes).round(2)
  end
  
  # Intelligence metrics
  def literacy_score
    # Weighted average of all batch literacy scores
    # Later batches count more (they build on earlier knowledge)
    scores = ingest_batches
      .where.not(literacy_score: nil)
      .pluck(:literacy_score, :created_at)
    
    return 0 if scores.empty?
    
    weighted_sum = scores.sum { |score, date| score * age_weight(date) }
    total_weight = scores.sum { |_, date| age_weight(date) }
    
    (weighted_sum / total_weight).round(1)
  end
  
  # Start a conversation with accumulated knowledge
  def start_conversation(session_id: nil)
    conversations.create!(
      session_id: session_id,
      metadata: {
        knowledge_state: {
          total_nodes: total_nodes,
          total_relationships: total_relationships,
          literacy_score: literacy_score,
          batch_count: ingest_batches.count
        }
      }
    )
  end
  
  # Ask a question using all accumulated knowledge
  def ask(question)
    # For now, query the graph with the question
    # Later this will use the conversational interface
    # Pass database name as positional argument
    Graph::QueryService.new(neo4j_database_name)
      .search_semantic(question)
  end
  
  # Lifecycle management
  def ensure_resources_exist!
    Rails.logger.info "Ensuring resources for EKN #{id}: #{name}"
    
    # Create Neo4j database ONCE (not per batch!)
    unless neo4j_database_exists?
      Rails.logger.info "Creating Neo4j database: #{neo4j_database_name}"
      Graph::Connection.instance.ensure_database_exists(neo4j_database_name)
    end
    
    # Create PostgreSQL schema
    unless postgres_schema_exists?
      Rails.logger.info "Creating PostgreSQL schema: #{postgres_schema_name}"
      ActiveRecord::Base.connection.execute(
        "CREATE SCHEMA IF NOT EXISTS #{postgres_schema_name}"
      )
    end
    
    # Create storage directory
    FileUtils.mkdir_p(storage_root_path)
  end
  
  def neo4j_database_exists?
    Graph::Connection.instance.database_exists?(neo4j_database_name)
  end
  
  def postgres_schema_exists?
    result = ActiveRecord::Base.connection.execute(
      "SELECT schema_name FROM information_schema.schemata WHERE schema_name = '#{postgres_schema_name}'"
    )
    result.any?
  end
  
  def destroy_resources!
    Rails.logger.warn "Destroying all resources for EKN #{id}: #{name}"
    
    # Drop Neo4j database
    if neo4j_database_exists?
      Graph::Connection.instance.drop_database(neo4j_database_name)
    end
    
    # Drop PostgreSQL schema
    if postgres_schema_exists?
      ActiveRecord::Base.connection.execute(
        "DROP SCHEMA IF EXISTS #{postgres_schema_name} CASCADE"
      )
    end
    
    # Remove storage directory
    FileUtils.rm_rf(storage_root_path) if storage_root_path.exist?
  end
  
  # Check if this is the Meta-Enliterator
  def is_meta?
    metadata&.dig('is_meta') == true
  end
  
  private
  
  def age_weight(date)
    # More recent batches get higher weight
    days_old = (Time.current - date) / 1.day
    1.0 / (1.0 + days_old * 0.01)
  end
end