# frozen_string_literal: true

module Graph
  # Orchestrates the graph assembly stage of the enliteration pipeline
  # Loads nodes and edges to Neo4j with constraint enforcement and deduplication
  class AssemblyJob < ApplicationJob
    queue_as :default

    def perform(ingest_batch_id)
      @batch = IngestBatch.find(ingest_batch_id)
      @stats = initialize_stats
      
      Rails.logger.info "Starting graph assembly for batch #{@batch.id}"
      @batch.update!(status: 'graph_assembly_in_progress')
      
      ActiveRecord::Base.transaction do
        Graph::Connection.instance.transaction do |tx|
          # 1. Setup Neo4j constraints and indexes
          setup_graph_schema(tx)
          
          # 2. Load nodes from all pools
          load_pool_nodes(tx)
          
          # 3. Load edges with verb glossary
          load_relationships(tx)
          
          # 4. Resolve duplicates
          resolve_duplicates(tx)
          
          # 5. Remove orphaned nodes
          remove_orphans(tx)
          
          # 6. Verify graph integrity
          verify_graph_integrity(tx)
        end
        
        # Update batch status
        @batch.update!(
          status: 'graph_assembly_completed',
          graph_assembly_stats: @stats,
          graph_assembled_at: Time.current
        )
      end
      
      Rails.logger.info "Graph assembly completed: #{@stats.inspect}"
      
      # Trigger next stage: Representation & Retrieval
      # Embedding::RepresentationJob.perform_later(@batch.id)
      
    rescue StandardError => e
      Rails.logger.error "Graph assembly failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      @batch.update!(
        status: 'graph_assembly_failed',
        graph_assembly_stats: @stats.merge(error: e.message)
      )
      
      raise
    end
    
    private
    
    def initialize_stats
      {
        nodes_created: 0,
        edges_created: 0,
        duplicates_resolved: 0,
        orphans_removed: 0,
        constraints_created: 0,
        indexes_created: 0,
        errors: []
      }
    end
    
    def setup_graph_schema(tx)
      Rails.logger.info "Setting up Neo4j constraints and indexes"
      
      schema_manager = Graph::SchemaManager.new(tx)
      result = schema_manager.setup
      
      @stats[:constraints_created] = result[:constraints_created]
      @stats[:indexes_created] = result[:indexes_created]
    end
    
    def load_pool_nodes(tx)
      Rails.logger.info "Loading nodes from all pools"
      
      node_loader = Graph::NodeLoader.new(tx, @batch)
      result = node_loader.load_all
      
      @stats[:nodes_created] = result[:total_nodes]
      @stats[:nodes_by_pool] = result[:by_pool]
    end
    
    def load_relationships(tx)
      Rails.logger.info "Loading relationships with verb glossary"
      
      edge_loader = Graph::EdgeLoader.new(tx, @batch)
      result = edge_loader.load_all
      
      @stats[:edges_created] = result[:total_edges]
      @stats[:edges_by_verb] = result[:by_verb]
      @stats[:reverse_edges_created] = result[:reverse_edges]
    end
    
    def resolve_duplicates(tx)
      Rails.logger.info "Resolving duplicate nodes"
      
      deduplicator = Graph::Deduplicator.new(tx)
      result = deduplicator.resolve_all
      
      @stats[:duplicates_resolved] = result[:resolved_count]
      @stats[:duplicate_merge_details] = result[:merge_details]
    end
    
    def remove_orphans(tx)
      Rails.logger.info "Removing orphaned nodes"
      
      orphan_remover = Graph::OrphanRemover.new(tx)
      result = orphan_remover.remove_all
      
      @stats[:orphans_removed] = result[:removed_count]
      @stats[:orphan_details] = result[:details]
    end
    
    def verify_graph_integrity(tx)
      Rails.logger.info "Verifying graph integrity"
      
      verifier = Graph::IntegrityVerifier.new(tx)
      result = verifier.verify_all
      
      unless result[:valid]
        @stats[:errors].concat(result[:errors])
        raise "Graph integrity check failed: #{result[:errors].join(', ')}"
      end
      
      @stats[:integrity_check] = result[:summary]
    end
  end
end