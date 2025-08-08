# == Schema Information
#
# Table name: ekns
#
#  id                  :bigint           not null, primary key
#  name                :string           not null
#  description         :text
#  status              :string           default("initializing")
#  domain_type         :string           default("general")
#  personality         :string           default("friendly")
#  session_id          :integer
#  metadata            :jsonb
#  settings            :jsonb
#  total_nodes         :integer          default(0)
#  total_relationships :integer          default(0)
#  total_items         :integer          default(0)
#  literacy_score      :float
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  slug                :string
#
# Indexes
#
#  index_ekns_on_metadata    (metadata) USING gin
#  index_ekns_on_session_id  (session_id)
#  index_ekns_on_slug        (slug) UNIQUE
#  index_ekns_on_status      (status)
#
class Ekn < ApplicationRecord
  extend FriendlyId
  friendly_id :name, use: [:slugged, :finders, :history]
  
  # :slugged - generates URL-safe slugs
  # :finders - allows Ekn.find() to work with slugs OR ids
  # :history - tracks slug changes if you rename an EKN
  
  # Associations - EKN owns everything
  has_many :ingest_batches, dependent: :destroy
  has_many :ekn_pipeline_runs, dependent: :destroy  # Pipeline runs for this EKN
  has_many :conversations, dependent: :destroy
  has_many :ingest_items, through: :ingest_batches
  has_many :api_calls, dependent: :nullify  # Track all API usage for this EKN
  has_many :sessions, dependent: :destroy  # All conversations with this EKN
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
    # Prefer stable, human-readable slug for Neo4j database naming
    # Fall back to id if slug is missing (e.g., before persistence)
    suffix = slug.presence || id
    "ekn-#{suffix}"
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
  
  # API Usage Analytics
  def api_usage_summary(period = :all_time)
    scope = case period
            when :today then api_calls.today
            when :this_week then api_calls.this_week
            when :this_month then api_calls.this_month
            else api_calls
            end
    
    {
      total_calls: scope.count,
      total_cost: scope.sum(:total_cost).to_f.round(4),
      total_tokens: scope.sum(:total_tokens),
      by_model: scope.group(:model_used).sum(:total_cost),
      by_endpoint: scope.group(:endpoint).count,
      by_service: scope.group(:service_name).count,
      success_rate: (scope.successful.count.to_f / scope.count * 100).round(2),
      avg_response_time: scope.average(:response_time_ms).to_f.round(2)
    }
  end
  
  def api_cost_breakdown
    {
      total: api_calls.sum(:total_cost).to_f.round(4),
      by_batch: ingest_batches.joins("INNER JOIN api_calls ON api_calls.trackable_id = ingest_batches.id AND api_calls.trackable_type = 'IngestBatch'")
                              .group("ingest_batches.name")
                              .sum("api_calls.total_cost"),
      by_session: sessions.joins(:api_calls)
                         .group("sessions.id")
                         .sum("api_calls.total_cost"),
      by_day: api_calls.group("DATE(created_at)").sum(:total_cost)
    }
  end
  
  def most_expensive_calls(limit = 10)
    api_calls.order(total_cost: :desc).limit(limit)
  end
  
  def api_usage_by_stage
    # Group API calls by pipeline stage
    {
      intake: api_calls.by_service('Ingest%').count,
      lexicon: api_calls.by_service('Lexicon%').count,
      pools: api_calls.by_service('Pools%').count,
      graph: api_calls.by_service('Graph%').count,
      embedding: api_calls.by_service('Embedding%').count,
      runtime: api_calls.by_service('Runtime%').count
    }
  end
  
  private
  
  def age_weight(date)
    # More recent batches get higher weight
    days_old = (Time.current - date) / 1.day
    1.0 / (1.0 + days_old * 0.01)
  end
end
