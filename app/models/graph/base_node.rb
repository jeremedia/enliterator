# Base class for Neo4j nodes using ActiveGraph
# This provides ActiveRecord-like interface for Neo4j entities
module Graph
  class BaseNode
    include ActiveGraph::Node
    include ActiveGraph::Timestamps # Handles created_at and updated_at automatically
    
    # Set database for this model based on EKN
    # ActiveGraph handles database switching via the driver
    def self.use_database(database_name)
      @database_name = database_name
    end
    
    def self.database_name
      @database_name || 'neo4j'
    end
    
    # Common ID property for all nodes
    id_property :uuid, auto: :uuid
  end
end