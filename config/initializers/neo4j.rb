# frozen_string_literal: true

require "neo4j/driver"

# Neo4j configuration
Rails.application.config.neo4j = {
  url: ENV.fetch("NEO4J_URL", "bolt://100.104.170.10:8687"),  # Neo4j Desktop on custom port
  username: ENV.fetch("NEO4J_USERNAME", ""),  # Auth disabled
  password: ENV.fetch("NEO4J_PASSWORD", ""),  # Auth disabled
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
      
      # Auth is disabled in Neo4j Desktop - use none
      @driver = Neo4j::Driver::GraphDatabase.driver(
        config[:url],
        Neo4j::Driver::AuthTokens.none,
        encryption: false,
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
    
    # Check if a database exists
    def database_exists?(database_name)
      session = @driver.session(database: 'system')
      result = session.run(
        "SHOW DATABASES WHERE name = $name",
        name: database_name
      )
      result.count > 0
    rescue Neo4j::Driver::Exceptions::ClientException => e
      # Community Edition doesn't support multi-database
      if e.message.include?("Unsupported administration command")
        Rails.logger.warn "Multi-database not supported. Using default database."
        return true  # Default database always exists
      end
      raise
    ensure
      session&.close
    end
    
    # Ensure a database exists (delegate to DatabaseManager)
    def ensure_database_exists(database_name)
      Graph::DatabaseManager.ensure_database_exists(database_name)
    end
    
    # Drop a database (delegate to DatabaseManager)
    def drop_database(database_name)
      Graph::DatabaseManager.drop_database(database_name)
    end
  end
end

# Ensure connection is closed on exit
at_exit do
  Graph::Connection.instance.close
end