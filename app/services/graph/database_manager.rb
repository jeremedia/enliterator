# Manages Neo4j databases for EKN isolation
# Each EKN gets its own dedicated database within the same Neo4j instance
# This provides complete data isolation between knowledge domains
#
# IMPORTANT: Production Architecture Decision
# ==========================================
# We use Neo4j's multi-database feature for complete isolation:
# - No data leakage between EKNs (medical data won't mix with festival data)
# - Database-level access control
# - Clean backup/restore per EKN
# - Performance isolation (separate indexes and caches)
#
module Graph
  class DatabaseManager
    class << self
      def ensure_database_exists(database_name)
        validate_database_name!(database_name)
        
        driver = Connection.instance.driver
        session = driver.session(database: 'system')
        
        # Check if database exists
        result = session.run(
          "SHOW DATABASES WHERE name = $name",
          name: database_name
        )
        
        if result.count == 0
          # Create database
          session.run(
            "CREATE DATABASE $name IF NOT EXISTS",
            name: database_name
          )
          Rails.logger.info "Created Neo4j database: #{database_name}"
          
          # Wait for database to come online
          wait_for_database(database_name)
          
          # Initialize schema constraints
          initialize_database_schema(database_name)
        else
          Rails.logger.debug "Neo4j database already exists: #{database_name}"
        end
        
        database_name
      rescue Neo4j::Driver::Exceptions::ClientException => e
        if e.message.include?("Unsupported administration command")
          Rails.logger.warn "Multi-database not supported (likely Community Edition). Using default database."
          return 'neo4j'
        end
        raise
      rescue => e
        Rails.logger.error "Failed to ensure database #{database_name}: #{e.message}"
        raise
      ensure
        session&.close
      end
      
      def drop_database(database_name)
        validate_database_name!(database_name)
        
        # Safety check - never drop the default database
        if database_name == 'neo4j' || database_name == 'system'
          raise ArgumentError, "Cannot drop system database: #{database_name}"
        end
        
        driver = Connection.instance.driver
        session = driver.session(database: 'system')
        
        # Stop database first
        session.run("STOP DATABASE $name", name: database_name)
        sleep 1
        
        # Drop database
        session.run("DROP DATABASE $name IF EXISTS", name: database_name)
        Rails.logger.info "Dropped Neo4j database: #{database_name}"
        
        true
      rescue Neo4j::Driver::Exceptions::ServiceException => e
        if e.message.include?("Unsupported administration command")
          Rails.logger.warn "Multi-database not supported. Cannot drop database."
          return false
        end
        raise
      rescue => e
        Rails.logger.error "Failed to drop database #{database_name}: #{e.message}"
        raise
      ensure
        session&.close
      end
      
      def list_ekn_databases
        driver = Connection.instance.driver
        session = driver.session(database: 'system')
        
        result = session.run(
          "SHOW DATABASES WHERE name STARTS WITH 'ekn_'"
        )
        
        databases = []
        result.each do |record|
          databases << {
            name: record['name'],
            status: record['currentStatus'],
            store_size: record['store']&.[]('totalSize'),
            created_at: record['createdAt']
          }
        end
        
        databases
      rescue Neo4j::Driver::Exceptions::ServiceException => e
        if e.message.include?("Unsupported administration command")
          Rails.logger.warn "Multi-database not supported. Returning default database only."
          return [{ name: 'neo4j', status: 'online' }]
        end
        raise
      ensure
        session&.close
      end
      
      def database_exists?(database_name)
        driver = Connection.instance.driver
        session = driver.session(database: 'system')
        
        result = session.run(
          "SHOW DATABASES WHERE name = $name",
          name: database_name
        )
        
        result.count > 0
      rescue Neo4j::Driver::Exceptions::ServiceException
        # If multi-database not supported, assume default database exists
        database_name == 'neo4j'
      ensure
        session&.close
      end
      
      def get_database_statistics(database_name)
        driver = Connection.instance.driver
        session = driver.session(database: database_name)
        
        # Node count
        node_result = session.run("MATCH (n) RETURN count(n) as count")
        node_count = node_result.single['count']
        
        # Relationship count
        rel_result = session.run("MATCH ()-[r]->() RETURN count(r) as count")
        rel_count = rel_result.single['count']
        
        # Node type distribution
        type_result = session.run(
          "MATCH (n) RETURN labels(n)[0] as type, count(n) as count ORDER BY count DESC"
        )
        
        node_types = {}
        type_result.each do |record|
          node_types[record['type']] = record['count']
        end
        
        {
          database_name: database_name,
          node_count: node_count,
          relationship_count: rel_count,
          node_types: node_types,
          status: 'online'
        }
      rescue => e
        Rails.logger.error "Failed to get statistics for #{database_name}: #{e.message}"
        {
          database_name: database_name,
          error: e.message,
          status: 'error'
        }
      ensure
        session&.close
      end
      
      private
      
      def validate_database_name!(name)
        unless name =~ /^ekn-[0-9]+$/
          raise ArgumentError, "Invalid database name: #{name}. Must match pattern 'ekn-[0-9]+'"
        end
      end
      
      def wait_for_database(database_name, timeout: 30)
        driver = Connection.instance.driver
        start_time = Time.now
        
        loop do
          begin
            session = driver.session(database: database_name)
            session.run("RETURN 1")
            session.close
            Rails.logger.debug "Database #{database_name} is online"
            break
          rescue => e
            if Time.now - start_time > timeout
              raise "Database #{database_name} did not come online within #{timeout} seconds"
            end
            Rails.logger.debug "Waiting for database #{database_name}... (#{e.class.name})"
            sleep 1
          end
        end
      end
      
      def initialize_database_schema(database_name)
        driver = Connection.instance.driver
        session = driver.session(database: database_name)
        
        # Create indexes for common queries
        constraints = [
          # Unique constraint on entity IDs
          "CREATE CONSTRAINT entity_id IF NOT EXISTS FOR (n:Entity) REQUIRE n.id IS UNIQUE",
          
          # Indexes for text search
          "CREATE INDEX entity_name IF NOT EXISTS FOR (n:Entity) ON (n.name)",
          "CREATE INDEX entity_label IF NOT EXISTS FOR (n:Entity) ON (n.label)",
          "CREATE INDEX entity_canonical IF NOT EXISTS FOR (n:Entity) ON (n.canonical)",
          
          # Pool-specific indexes
          "CREATE INDEX idea_name IF NOT EXISTS FOR (n:Idea) ON (n.name)",
          "CREATE INDEX manifest_name IF NOT EXISTS FOR (n:Manifest) ON (n.name)",
          "CREATE INDEX experience_name IF NOT EXISTS FOR (n:Experience) ON (n.name)",
          "CREATE INDEX relational_name IF NOT EXISTS FOR (n:Relational) ON (n.name)",
          "CREATE INDEX evolutionary_name IF NOT EXISTS FOR (n:Evolutionary) ON (n.name)",
          "CREATE INDEX practical_name IF NOT EXISTS FOR (n:Practical) ON (n.name)",
          "CREATE INDEX emanation_name IF NOT EXISTS FOR (n:Emanation) ON (n.name)"
        ]
        
        constraints.each do |constraint|
          begin
            session.run(constraint)
            Rails.logger.debug "Created constraint/index: #{constraint.split(' ')[2]}"
          rescue Neo4j::Driver::Exceptions::ClientException => e
            # Index might already exist, which is fine
            Rails.logger.debug "Constraint/index might already exist: #{e.message}"
          end
        end
        
        Rails.logger.info "Initialized schema for database: #{database_name}"
      rescue => e
        Rails.logger.error "Failed to initialize schema for #{database_name}: #{e.message}"
        # Don't fail if schema init fails - database is still usable
      ensure
        session&.close
      end
    end
  end
end