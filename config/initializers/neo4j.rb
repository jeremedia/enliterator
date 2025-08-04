# frozen_string_literal: true

require "neo4j/driver"

# Neo4j configuration
Rails.application.config.neo4j = {
  url: ENV.fetch("NEO4J_URL", "bolt://localhost:7687"),
  username: ENV.fetch("NEO4J_USERNAME", "neo4j"),
  password: ENV.fetch("NEO4J_PASSWORD", "enliterator_dev"),
  encryption: Rails.env.production?,
  pool_size: ENV.fetch("NEO4J_POOL_SIZE", 10).to_i,
  connection_timeout: 30,
  max_retry_time: 15
}

# Create singleton connection manager
module Graph
  class Connection
    include Singleton
    
    attr_reader :driver
    
    def initialize
      config = Rails.application.config.neo4j
      
      @driver = Neo4j::Driver::GraphDatabase.driver(
        config[:url],
        Neo4j::Driver::AuthTokens.basic(config[:username], config[:password]),
        encryption: config[:encryption],
        max_connection_pool_size: config[:pool_size],
        connection_timeout: config[:connection_timeout],
        max_retry_time: config[:max_retry_time]
      )
    end
    
    def session(&block)
      @driver.session(&block)
    end
    
    def transaction(&block)
      session do |session|
        session.write_transaction(&block)
      end
    end
    
    def read_transaction(&block)
      session do |session|
        session.read_transaction(&block)
      end
    end
    
    def close
      @driver.close if @driver
    end
  end
end

# Ensure connection is closed on exit
at_exit do
  Graph::Connection.instance.close
end