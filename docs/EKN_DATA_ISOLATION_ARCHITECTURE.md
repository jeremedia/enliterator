# EKN Data Isolation Architecture

## Executive Summary
Each Enliterated Knowledge Navigator (EKN) must have completely isolated data. Mixing data from different knowledge domains violates the core principles of Enliterator and creates security, privacy, and semantic confusion issues.

## Current Problem
- The default `neo4j` database contains 280k+ nodes from Burning Man data
- New EKNs are trying to use the same database
- batch_id filtering is insufficient for true isolation
- Data from medical research could mix with festival data - unacceptable

## Recommended Solution: Database-per-EKN

### Architecture Decision
**Use Neo4j's multi-database feature**: Each EKN gets its own dedicated database within the same Neo4j instance.

### Why This Approach?
1. **Complete Isolation**: No data leakage between EKNs
2. **Performance**: Each database has its own indexes and query cache
3. **Security**: Database-level access control possible
4. **Backup/Restore**: Can backup individual EKNs
5. **Deletion**: Clean removal with `DROP DATABASE`
6. **Scalability**: Neo4j 2025 supports thousands of databases
7. **Resource Efficiency**: Single Neo4j instance, multiple isolated graphs

### Implementation Pattern

```ruby
# app/models/ingest_batch.rb
class IngestBatch < ApplicationRecord
  def neo4j_database_name
    # Use a sanitized version of the EKN ID
    "ekn_#{id.to_s.gsub(/[^a-z0-9_]/i, '_').downcase}"
  end
  
  def ensure_neo4j_database_exists!
    Graph::DatabaseManager.ensure_database_exists(neo4j_database_name)
  end
  
  def drop_neo4j_database!
    Graph::DatabaseManager.drop_database(neo4j_database_name)
  end
end
```

```ruby
# app/services/graph/database_manager.rb
module Graph
  class DatabaseManager
    class << self
      def ensure_database_exists(database_name)
        driver = Connection.instance.driver
        session = driver.session(database: 'system')
        
        # Check if database exists
        result = session.run("SHOW DATABASES WHERE name = $name", name: database_name)
        
        if result.count == 0
          # Create database
          session.run("CREATE DATABASE $name IF NOT EXISTS", name: database_name)
          Rails.logger.info "Created Neo4j database: #{database_name}"
          
          # Wait for database to come online
          wait_for_database(database_name)
        end
        
        session.close
      rescue => e
        Rails.logger.error "Failed to ensure database #{database_name}: #{e.message}"
        raise
      end
      
      def drop_database(database_name)
        return if database_name == 'neo4j' # Never drop the default database
        
        driver = Connection.instance.driver
        session = driver.session(database: 'system')
        
        session.run("DROP DATABASE $name IF EXISTS", name: database_name)
        Rails.logger.info "Dropped Neo4j database: #{database_name}"
        
        session.close
      end
      
      private
      
      def wait_for_database(database_name, timeout: 30)
        driver = Connection.instance.driver
        start_time = Time.now
        
        loop do
          begin
            session = driver.session(database: database_name)
            session.run("RETURN 1")
            session.close
            break
          rescue => e
            if Time.now - start_time > timeout
              raise "Database #{database_name} did not come online within #{timeout} seconds"
            end
            sleep 1
          end
        end
      end
    end
  end
end
```

```ruby
# app/services/graph/query_service.rb
module Graph
  class QueryService
    def initialize(ekn_or_database_name)
      if ekn_or_database_name.is_a?(IngestBatch)
        @ekn = ekn_or_database_name
        @database_name = @ekn.neo4j_database_name
        @ekn.ensure_neo4j_database_exists!
      elsif ekn_or_database_name.is_a?(String)
        @database_name = ekn_or_database_name
      else
        @database_name = 'neo4j' # Default database for exploration
      end
      
      @driver = Connection.instance.driver
    end
    
    def session(&block)
      @driver.session(database: @database_name, &block)
    end
    
    # All query methods now use the scoped session
    def search_entities(query, limit: 10)
      session do |s|
        # Queries automatically go to the right database
        result = s.run("MATCH (n) WHERE n.name CONTAINS $query RETURN n LIMIT $limit",
                      query: query, limit: limit)
        # ...
      end
    end
  end
end
```

### Migration Strategy

#### Phase 1: New EKNs (Immediate)
- All new EKNs create their own database
- Modify pipeline Stage 5 (Graph Assembly) to use dedicated database

#### Phase 2: Existing Data (Short-term)
1. Create database `ekn_burning_man_2024` for existing BM data
2. Export existing data: `neo4j-admin database dump neo4j`
3. Import into new database: `neo4j-admin database load ekn_burning_man_2024`
4. Update any existing IngestBatch records

#### Phase 3: Clean Default Database (Medium-term)
- Clear the default `neo4j` database
- Use it only for system/admin purposes

### Database Naming Convention
```
ekn_<ingest_batch_id>

Examples:
- ekn_1 (first EKN)
- ekn_42 (42nd EKN)
- ekn_burning_man_2024 (legacy migration)
```

### Lifecycle Management

```ruby
# When creating an EKN
batch = IngestBatch.create!(name: "Medical Research 2025")
batch.ensure_neo4j_database_exists!

# When deleting an EKN
batch.drop_neo4j_database!
batch.destroy!

# When querying an EKN
service = Graph::QueryService.new(batch)
nodes = service.search_entities("cancer")
```

### Considerations

#### Resource Limits
- Neo4j Community Edition: Limited number of databases
- Neo4j Enterprise: Unlimited databases
- Each database uses memory for caching

#### Backup Strategy
```bash
# Backup individual EKN
neo4j-admin database dump ekn_42 --to-path=/backups/

# Restore individual EKN
neo4j-admin database load ekn_42 --from-path=/backups/ekn_42.dump
```

#### Monitoring
```cypher
// Check all EKN databases
SHOW DATABASES WHERE name STARTS WITH 'ekn_'

// Check database size
CALL apoc.meta.stats() YIELD nodeCount, relCount, database
```

### Security Benefits
1. **Complete Isolation**: No cross-contamination possible
2. **Access Control**: Can set per-database permissions
3. **Audit Trail**: Database-level logging
4. **Compliance**: Data residency requirements easier to meet

### Performance Benefits
1. **Indexes**: Each EKN has its own optimized indexes
2. **Caching**: Independent query caches
3. **Concurrent Access**: No lock contention between EKNs
4. **Scaling**: Can move large EKNs to dedicated instances

## Implementation Checklist

- [ ] Create Graph::DatabaseManager service
- [ ] Update IngestBatch model with database methods
- [ ] Modify Graph::QueryService to use database parameter
- [ ] Update all Graph writers to use correct database
- [ ] Update Stage 5 (Graph Assembly) to create/use EKN database
- [ ] Add database cleanup to EKN deletion
- [ ] Create migration for existing data
- [ ] Update documentation
- [ ] Add database monitoring dashboard
- [ ] Implement backup/restore rake tasks

## Testing Strategy

```ruby
# spec/services/graph/database_manager_spec.rb
RSpec.describe Graph::DatabaseManager do
  it "creates a new database for an EKN" do
    batch = create(:ingest_batch)
    expect { batch.ensure_neo4j_database_exists! }
      .to change { neo4j_database_count }.by(1)
  end
  
  it "isolates data between EKNs" do
    ekn1 = create(:ingest_batch)
    ekn2 = create(:ingest_batch)
    
    # Add data to EKN1
    service1 = Graph::QueryService.new(ekn1)
    service1.create_node(name: "Secret Data")
    
    # Verify EKN2 can't see it
    service2 = Graph::QueryService.new(ekn2)
    expect(service2.search_entities("Secret")).to be_empty
  end
end
```

## Conclusion

Database-per-EKN is the correct long-term architecture for Enliterator. It provides:
- **True isolation** between knowledge domains
- **Security** for sensitive datasets
- **Performance** through independent optimization
- **Scalability** to thousands of EKNs
- **Simplicity** in backup/restore/deletion

This is not premature optimization - it's fundamental architecture that prevents catastrophic data mixing between unrelated knowledge domains.