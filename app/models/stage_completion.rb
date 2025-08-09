# frozen_string_literal: true

class StageCompletion < ApplicationRecord
  belongs_to :ingest_batch
  belongs_to :ekn
  
  STATUSES = %w[pending checking skipped in_progress completed failed].freeze
  
  # Stage definitions with their expensive operations marked
  STAGES = {
    0 => { name: 'frame_mission', expensive: false },
    1 => { name: 'intake', expensive: false },
    2 => { name: 'rights_provenance', expensive: false },
    3 => { name: 'lexicon_bootstrap', expensive: true }, # OpenAI for canonical terms
    4 => { name: 'pool_filling', expensive: true }, # Heavy OpenAI usage for entity extraction
    5 => { name: 'graph_assembly', expensive: false },
    5.5 => { name: 'relationship_discovery', expensive: true }, # OpenAI for relationship extraction
    6 => { name: 'embeddings', expensive: true }, # OpenAI batch API for embeddings
    7 => { name: 'literacy_scoring', expensive: false },
    8 => { name: 'deliverables', expensive: false }
  }.freeze
  
  validates :status, inclusion: { in: STATUSES }
  validates :stage_number, uniqueness: { scope: :ingest_batch_id }
  
  scope :expensive_stages, -> { where(stage_number: [3, 4, 5.5, 6]) }
  scope :completed, -> { where(status: 'completed') }
  scope :skipped, -> { where(status: 'skipped') }
  
  def expensive?
    STAGES[stage_number][:expensive]
  end
  
  def can_be_skipped?
    return false if status == 'completed' # Already done
    return false if status == 'in_progress' # Currently running
    
    # Check stage-specific completion criteria
    case stage_number
    when 4 # Pool Filling - Most expensive!
      check_pool_filling_completion
    when 6 # Embeddings - Also expensive
      check_embeddings_completion
    when 3 # Lexicon Bootstrap
      check_lexicon_completion
    when 5.5 # Relationship Discovery
      check_relationship_completion
    else
      check_standard_completion
    end
  end
  
  def skip!(reason)
    update!(
      status: 'skipped',
      skip_reason: reason,
      checked_at: Time.current,
      completion_metrics: calculate_completion_metrics
    )
  end
  
  private
  
  def check_pool_filling_completion
    # Check if entities already extracted for this batch
    total_items = ingest_batch.ingest_items.count
    return false if total_items == 0
    
    # Check each pool for extracted entities
    extracted_counts = {
      ideas: ingest_batch.ideas.count,
      practicals: ingest_batch.practicals.count,
      experiences: ingest_batch.experiences.count,
      manifests: ingest_batch.manifests.count,
      characters: ingest_batch.characters.count,
      times: ingest_batch.times.count,
      spaces: ingest_batch.spaces.count,
      lifecycles: ingest_batch.lifecycles.count,
      symbolics: ingest_batch.symbolics.count,
      relators: ingest_batch.relators.count
    }
    
    # Must have entities in at least 3 pools
    pools_with_entities = extracted_counts.values.count { |c| c > 0 }
    return false if pools_with_entities < 3
    
    # Check coverage rate (entities per item)
    total_entities = extracted_counts.values.sum
    coverage_rate = total_entities.to_f / total_items
    
    # Log metrics
    self.completion_metrics = {
      extracted_counts: extracted_counts,
      pools_with_entities: pools_with_entities,
      coverage_rate: coverage_rate,
      total_entities: total_entities,
      total_items: total_items
    }
    
    # Skip if coverage is good enough (multiple entities per item expected)
    coverage_rate >= 2.0 # Average 2+ entities per item
  end
  
  def check_embeddings_completion
    # Check if embeddings already exist
    return false unless ekn.neo4j_database_name
    
    # Count entities in Neo4j that need embeddings
    entity_count = count_neo4j_nodes
    return false if entity_count == 0
    
    # Count existing embeddings
    embedding_count = 0
    
    # Check Neo4j for embeddings
    driver = Graph::Connection.instance.driver
    driver.session(database: ekn.neo4j_database_name) do |session|
      session.read_transaction do |tx|
        result = tx.run(<<~CYPHER
          MATCH (n)
          WHERE n.batch_id = $batch_id
            AND n.embedding IS NOT NULL
          RETURN count(n) as count
        CYPHER
        , batch_id: ingest_batch.id)
        
        embedding_count = result.single['count']
      end
    end
    
    coverage = embedding_count.to_f / entity_count
    
    self.completion_metrics = {
      entity_count: entity_count,
      embedding_count: embedding_count,
      coverage: coverage
    }
    
    # Skip if 95% have embeddings
    coverage >= 0.95
  end
  
  def check_lexicon_completion
    # Check if lexicon entries exist
    lexicon_count = ingest_batch.lexicon_entries.count
    item_count = ingest_batch.ingest_items.count
    
    return false if item_count == 0
    
    # Should have multiple lexicon entries per item
    coverage = lexicon_count.to_f / item_count
    
    self.completion_metrics = {
      lexicon_count: lexicon_count,
      item_count: item_count,
      coverage: coverage
    }
    
    coverage >= 1.0 # At least 1 lexicon entry per item
  end
  
  def check_relationship_completion
    return false unless ekn.neo4j_database_name
    
    # Check graph density
    driver = Graph::Connection.instance.driver
    metrics = {}
    
    driver.session(database: ekn.neo4j_database_name) do |session|
      session.read_transaction do |tx|
        # Count nodes
        node_count = tx.run(<<~CYPHER
          MATCH (n) WHERE n.batch_id = $batch_id
          RETURN count(n) as count
        CYPHER
        , batch_id: ingest_batch.id).single['count']
        
        # Count edges
        edge_count = tx.run(<<~CYPHER
          MATCH (n)-[r]-(m)
          WHERE n.batch_id = $batch_id
            AND m.batch_id = $batch_id
            AND type(r) <> 'HAS_RIGHTS'
          RETURN count(DISTINCT r) as count
        CYPHER
        , batch_id: ingest_batch.id).single['count']
        
        return false if node_count < 2
        
        max_edges = (node_count * (node_count - 1)) / 2.0
        density = edge_count.to_f / max_edges
        
        metrics = {
          node_count: node_count,
          edge_count: edge_count,
          density: density
        }
      end
    end
    
    self.completion_metrics = metrics
    
    # Skip if density is acceptable
    metrics[:density] >= 0.001 # Very low threshold for now
  end
  
  def check_standard_completion
    # For non-expensive stages, check basic completion
    case stage_number
    when 1 # Intake
      ingest_batch.ingest_items.count > 0
    when 2 # Rights
      ingest_batch.ingest_items.where(rights_id: nil).count == 0
    when 5 # Graph Assembly
      count_neo4j_nodes > 0
    when 7 # Literacy Scoring
      ingest_batch.literacy_scores.exists?
    when 8 # Deliverables
      ingest_batch.prompt_packs.exists?
    else
      false # Don't skip by default
    end
  end
  
  def count_neo4j_nodes
    return 0 unless ekn.neo4j_database_name
    
    driver = Graph::Connection.instance.driver
    count = 0
    
    driver.session(database: ekn.neo4j_database_name) do |session|
      session.read_transaction do |tx|
        result = tx.run(<<~CYPHER
          MATCH (n) WHERE n.batch_id = $batch_id
          RETURN count(n) as count
        CYPHER
        , batch_id: ingest_batch.id)
        
        count = result.single['count']
      end
    end
    
    count
  rescue => e
    Rails.logger.error "Failed to count Neo4j nodes: #{e.message}"
    0
  end
  
  def calculate_completion_metrics
    # Implemented by stage-specific check methods
    completion_metrics || {}
  end
end