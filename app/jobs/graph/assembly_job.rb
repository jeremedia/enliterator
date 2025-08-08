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
        
        # CRITICAL: Schema operations MUST be in completely separate session and transaction
        # Neo4j does not allow schema changes and data changes in the same transaction
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
    end
    
    def resolve_duplicates(tx)
      deduplicator = Graph::Deduplicator.new(tx)
      result = deduplicator.resolve_all
      @stats[:duplicates_resolved] = result[:resolved_count]
    end
    
    def collect_stage_metrics
      @stats
    end
  end
end
