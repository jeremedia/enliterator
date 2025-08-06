# frozen_string_literal: true

module Graph
  # Helper module to ensure all code uses the same Neo4j connection
  # Include this module in any class that needs Neo4j access
  module ConnectionHelper
    extend ActiveSupport::Concern
    
    included do
      # Make these available as instance methods
      delegate :neo4j_driver, :neo4j_session, :neo4j_transaction, to: :class
    end
    
    class_methods do
      # Get the singleton Neo4j driver
      def neo4j_driver
        Graph::Connection.instance.driver
      end
      
      # Get a Neo4j session (optionally for a specific database)
      def neo4j_session(database: nil, &block)
        if block_given?
          if database
            neo4j_driver.session(database: database, &block)
          else
            neo4j_driver.session(&block)
          end
        else
          if database
            neo4j_driver.session(database: database)
          else
            neo4j_driver.session
          end
        end
      end
      
      # Execute a write transaction
      def neo4j_transaction(database: nil, &block)
        neo4j_session(database: database) do |session|
          session.write_transaction(&block)
        end
      end
      
      # Execute a read transaction
      def neo4j_read_transaction(database: nil, &block)
        neo4j_session(database: database) do |session|
          session.read_transaction(&block)
        end
      end
      
      # Test if connection is working
      def neo4j_connected?
        neo4j_session do |session|
          result = session.run("RETURN 1 as test")
          result.single['test'] == 1
        end
      rescue => e
        Rails.logger.error "Neo4j connection test failed: #{e.message}"
        false
      end
      
      # Get connection info for debugging
      def neo4j_connection_info
        config = Rails.application.config.neo4j
        {
          url: config[:url],
          connected: neo4j_connected?,
          databases: list_databases
        }
      end
      
      private
      
      def list_databases
        neo4j_session(database: 'system') do |session|
          result = session.run("SHOW DATABASES")
          result.map { |r| r['name'] }
        end
      rescue
        ['neo4j'] # Default database if listing fails
      end
    end
  end
end