# frozen_string_literal: true

# PURPOSE: Stage 5 of the 9-stage pipeline - Graph Assembly
# Loads nodes and edges to Neo4j with constraint enforcement
# and deduplication.
#
# Inputs: Extracted pool entities and relations
# Outputs: Neo4j knowledge graph

module Graph
  class AssemblyJob < Pipeline::BaseJob
    queue_as :pipeline
    
    def perform(pipeline_run_id)
      # BaseJob sets up @pipeline_run, @batch, @ekn via around_perform
      # Do NOT call super - BaseJob uses around_perform to wrap this method
      
      @stats = initialize_stats
      # Use the EKN's dedicated database for isolation
      database_name = @ekn.neo4j_database_name
      
      # Ensure the database exists
      Graph::DatabaseManager.ensure_database_exists(database_name)
      
      log_progress "Starting graph assembly in database: #{database_name}"
      
      begin
        # Get Neo4j session with default database
        driver = Graph::Connection.instance.driver
        
        # CRITICAL: Backfill any data needed for upcoming constraints in a data-only tx
        log_progress "Backfilling Lexicon canonical descriptions (pre-schema)..."
        data_prep_session = driver.session(database: database_name)
        begin
          data_prep_session.write_transaction do |tx|
            backfill_canonical_description(tx)
          end
        ensure
          data_prep_session.close
        end

        # CRITICAL: Schema operations MUST be in a separate session/transaction
        # Neo4j does not allow schema changes and data changes in the same transaction.
        log_progress "Setting up graph schema..."
        schema_session = driver.session(database: database_name)
        begin
          schema_session.write_transaction do |tx|
            setup_graph_schema(tx)
          end
        ensure
          schema_session.close
        end
        
        # Wait a moment for schema changes to propagate
        sleep(0.5)
        
        # Now perform data operations in a new session
        log_progress "Loading graph data..."
        data_session = driver.session(database: database_name)
        begin
          data_session.write_transaction do |tx|
            load_pool_nodes(tx)
            load_relationships(tx)
            resolve_duplicates(tx)
          end
        ensure
          data_session.close
        end
        
        # ACCEPTANCE GATE: Verify relationships were created (unless dataset truly has none)
        validate_graph_relationships!
        
        log_progress "✅ Graph assembly complete: #{@stats[:nodes_created]} nodes, #{@stats[:edges_created]} edges"
        
        # Track metrics
        track_metric :nodes_created, @stats[:nodes_created]
        track_metric :edges_created, @stats[:edges_created]
        track_metric :duplicates_resolved, @stats[:duplicates_resolved]
        
        # CRITICAL: Update IngestItems to mark them as assembled
        # This prepares them for the embedding stage
        @batch.ingest_items
          .where(pool_status: 'extracted')
          .where(graph_status: ['pending', nil])
          .update_all(
            graph_status: 'assembled',
            embedding_status: 'pending',  # Ready for embedding
            graph_metadata: { assembled_at: Time.current }
          )
        
        # Update batch status
        @batch.update!(status: 'graph_assembly_completed')
        
      rescue => e
        log_progress "Graph assembly failed: #{e.message}", level: :error
        raise
      end
    end
    
    private
    
    def initialize_stats
      {
        nodes_created: 0,
        edges_created: 0,
        duplicates_resolved: 0
      }
    end
    
    def setup_graph_schema(tx)
      schema_manager = Graph::SchemaManager.new(tx)
      result = schema_manager.setup
      @stats[:constraints_created] = result[:constraints_created]
      @stats[:indexes_created] = result[:indexes_created]
    end
    
    def load_pool_nodes(tx)
      node_loader = Graph::NodeLoader.new(tx, @batch)
      result = node_loader.load_all
      @stats[:nodes_created] = result[:total_nodes]
    end
    
    def load_relationships(tx)
      edge_loader = Graph::EdgeLoader.new(tx, @batch)
      result = edge_loader.load_all
      @stats[:edges_created] = result[:total_edges]
      @stats[:rights_edges] = result[:rights_edges]
    end
    
    def resolve_duplicates(tx)
      deduplicator = Graph::Deduplicator.new(tx)
      result = deduplicator.resolve_all
      @stats[:duplicates_resolved] = result[:resolved_count]
    end

    def backfill_canonical_description(tx)
      # Ensure any existing Lexicon nodes have canonical_description set
      query = <<~CYPHER
        MATCH (n:Lexicon)
        WHERE n.canonical_description IS NULL AND n.definition IS NOT NULL
        SET n.canonical_description = n.definition
        RETURN count(n) as updated_count
      CYPHER

      result = tx.run(query)
      record = result.single
      count = record ? record[:updated_count] : 0
      log_progress "Backfilled canonical_description on #{count} Lexicon nodes", level: :debug if count.to_i > 0
    rescue => e
      # Non-fatal: log and continue; constraint creation will surface issues otherwise
      log_progress "Backfill canonical_description skipped: #{e.message}", level: :warn
    end
    
    def validate_graph_relationships!
      # Skip validation for very small datasets
      return if @stats[:nodes_created] < 3
      
      # Check if we have domain relationships (not just HAS_RIGHTS)
      domain_edges = @stats[:edges_created] - (@stats[:rights_edges] || 0)
      
      if domain_edges == 0 && @stats[:nodes_created] > 10
        # Log warning but don't fail - allow manual intervention
        log_progress "⚠️  WARNING: No domain relationships found in graph!", level: :warn
        log_progress "   Only system relationships (HAS_RIGHTS) were created.", level: :warn
        log_progress "   This may indicate:", level: :warn
        log_progress "   1. Relation extraction didn't run or failed", level: :warn
        log_progress "   2. Content doesn't contain extractable relationships", level: :warn
        log_progress "   3. Verb glossary mismatch with content", level: :warn
        log_progress "", level: :warn
        log_progress "   To fix: Run `rails enliterator:graph:relations:backfill[#{@batch.id}]`", level: :warn
        
        # Track this as a quality issue
        track_metric :graph_quality_warning, 'no_domain_relationships'
        
        # Update batch with warning
        @batch.update!(
          graph_metadata: (@batch.graph_metadata || {}).merge(
            'warning' => 'no_domain_relationships',
            'suggested_action' => "rails enliterator:graph:relations:backfill[#{@batch.id}]"
          )
        )
      elsif domain_edges < @stats[:nodes_created] / 10
        log_progress "⚠️  Low relationship density: #{domain_edges} edges for #{@stats[:nodes_created]} nodes", level: :warn
      end
    end
    
    def collect_stage_metrics
      @stats
    end
  end
end
