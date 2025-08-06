# Complete EKN Data Isolation Architecture

## Executive Summary
Each EKN must have COMPLETE isolation across all data layers: Neo4j graphs, PostgreSQL embeddings, source files, and derived artifacts. This document defines the production architecture for true multi-tenant isolation.

## Current State vs Target State

### Current State (PROBLEMATIC)
- Neo4j: Shared database with 280k mixed nodes
- PostgreSQL: Shared tables with batch_id filtering
- Files: Unknown/mixed storage
- Embeddings: Shared pgvector table
- Security: No real isolation

### Target State (PRODUCTION-READY)
- Neo4j: Database-per-EKN
- PostgreSQL: Schema-per-EKN  
- Files: Isolated storage per EKN
- Embeddings: Isolated vector stores
- Security: Complete data isolation

## Recommended Architecture: Hybrid Isolation

### Why NOT Docker Compose per EKN?
While tempting, full containerization per EKN has significant drawbacks:
- **Resource overhead**: Each EKN needs PostgreSQL, Neo4j, Redis instances
- **Complexity**: Managing 100s of Docker Compose stacks
- **Networking**: Complex inter-container communication
- **Monitoring**: Harder to monitor distributed containers
- **Cost**: 10-100x more expensive in cloud environments

### Recommended: Logical Isolation with Shared Infrastructure

```
┌─────────────────────────────────────────────────────────┐
│                     EKN: Medical Research 2025          │
├─────────────────────────────────────────────────────────┤
│ PostgreSQL Schema: ekn_42                               │
│ Neo4j Database: ekn_42                                  │
│ File Storage: /storage/ekn_42/ (or s3://ekns/42/)      │
│ Redis Namespace: ekn:42:*                               │
│ Embeddings: ekn_42.embeddings table                     │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│                     EKN: Burning Man 2024               │
├─────────────────────────────────────────────────────────┤
│ PostgreSQL Schema: ekn_1                                │
│ Neo4j Database: ekn_1                                   │
│ File Storage: /storage/ekn_1/ (or s3://ekns/1/)        │
│ Redis Namespace: ekn:1:*                                │
│ Embeddings: ekn_1.embeddings table                      │
└─────────────────────────────────────────────────────────┘
```

## Implementation Details

### 1. PostgreSQL Schema Isolation

```ruby
# app/models/ingest_batch.rb
class IngestBatch < ApplicationRecord
  def postgres_schema_name
    "ekn_#{id}"
  end
  
  def ensure_postgres_schema_exists!
    ApplicationRecord.connection.execute(<<-SQL)
      CREATE SCHEMA IF NOT EXISTS #{postgres_schema_name};
      
      -- Create isolated embeddings table with pgvector
      CREATE TABLE IF NOT EXISTS #{postgres_schema_name}.embeddings (
        id BIGSERIAL PRIMARY KEY,
        entity_id VARCHAR NOT NULL,
        entity_type VARCHAR NOT NULL,
        content TEXT,
        embedding vector(1536),
        metadata JSONB DEFAULT '{}',
        created_at TIMESTAMP DEFAULT NOW(),
        updated_at TIMESTAMP DEFAULT NOW()
      );
      
      -- Create HNSW index for similarity search
      CREATE INDEX IF NOT EXISTS idx_#{postgres_schema_name}_embeddings_hnsw 
      ON #{postgres_schema_name}.embeddings 
      USING hnsw (embedding vector_cosine_ops);
      
      -- Create other isolated tables
      CREATE TABLE IF NOT EXISTS #{postgres_schema_name}.documents (
        id BIGSERIAL PRIMARY KEY,
        path VARCHAR NOT NULL,
        content TEXT,
        mime_type VARCHAR,
        size_bytes BIGINT,
        hash VARCHAR,
        metadata JSONB DEFAULT '{}',
        created_at TIMESTAMP DEFAULT NOW()
      );
      
      CREATE TABLE IF NOT EXISTS #{postgres_schema_name}.entities (
        id BIGSERIAL PRIMARY KEY,
        neo4j_id VARCHAR,
        name VARCHAR NOT NULL,
        canonical_name VARCHAR,
        pool VARCHAR,
        surface_forms TEXT[],
        created_at TIMESTAMP DEFAULT NOW()
      );
    SQL
  end
  
  def drop_postgres_schema!
    ApplicationRecord.connection.execute(<<-SQL)
      DROP SCHEMA IF EXISTS #{postgres_schema_name} CASCADE;
    SQL
  end
end
```

### 2. File Storage Isolation

```ruby
# app/services/storage/ekn_storage.rb
module Storage
  class EknStorage
    def initialize(ekn)
      @ekn = ekn
      @storage_type = ENV.fetch('STORAGE_TYPE', 'filesystem')
    end
    
    def root_path
      case @storage_type
      when 'filesystem'
        Rails.root.join('storage', 'ekns', @ekn.id.to_s)
      when 's3'
        "s3://#{ENV['S3_BUCKET']}/ekns/#{@ekn.id}/"
      when 'gcs'
        "gs://#{ENV['GCS_BUCKET']}/ekns/#{@ekn.id}/"
      end
    end
    
    def ensure_storage_exists!
      case @storage_type
      when 'filesystem'
        FileUtils.mkdir_p(root_path)
        FileUtils.mkdir_p(root_path.join('uploads'))
        FileUtils.mkdir_p(root_path.join('processed'))
        FileUtils.mkdir_p(root_path.join('exports'))
      when 's3'
        # S3 paths are created on demand
      end
    end
    
    def store_file(file, category: 'uploads')
      path = File.join(root_path, category, SecureRandom.uuid, file.original_filename)
      
      case @storage_type
      when 'filesystem'
        FileUtils.mkdir_p(File.dirname(path))
        File.binwrite(path, file.read)
      when 's3'
        s3_client.put_object(
          bucket: ENV['S3_BUCKET'],
          key: path,
          body: file
        )
      end
      
      path
    end
    
    def destroy_all_storage!
      case @storage_type
      when 'filesystem'
        FileUtils.rm_rf(root_path) if root_path.to_s.include?('/ekns/')
      when 's3'
        # List and delete all objects with prefix
        s3_client.list_objects_v2(
          bucket: ENV['S3_BUCKET'],
          prefix: "ekns/#{@ekn.id}/"
        ).contents.each do |object|
          s3_client.delete_object(
            bucket: ENV['S3_BUCKET'],
            key: object.key
          )
        end
      end
    end
  end
end
```

### 3. Embedding Service with Schema Isolation

```ruby
# app/services/embedding/schema_aware_service.rb
module Embedding
  class SchemaAwareService
    def initialize(ekn)
      @ekn = ekn
      @schema = ekn.postgres_schema_name
      @client = OPENAI
    end
    
    def embed_text(text, metadata = {})
      # Get embedding from OpenAI
      response = @client.embeddings(
        parameters: {
          model: OpenaiConfig::SettingsManager.model_for('embedding'),
          input: text
        }
      )
      
      embedding = response.dig('data', 0, 'embedding')
      
      # Store in schema-specific table
      ApplicationRecord.connection.execute(<<-SQL)
        INSERT INTO #{@schema}.embeddings (
          entity_id, entity_type, content, embedding, metadata
        ) VALUES (
          '#{metadata[:entity_id]}',
          '#{metadata[:entity_type]}',
          '#{ApplicationRecord.connection.quote(text)}',
          '#{embedding}',
          '#{metadata.to_json}'::jsonb
        )
      SQL
    end
    
    def search(query, limit: 10)
      # Get query embedding
      response = @client.embeddings(
        parameters: {
          model: OpenaiConfig::SettingsManager.model_for('embedding'),
          input: query
        }
      )
      
      query_embedding = response.dig('data', 0, 'embedding')
      
      # Search in schema-specific table
      results = ApplicationRecord.connection.execute(<<-SQL)
        SELECT 
          entity_id,
          entity_type,
          content,
          metadata,
          embedding <=> '#{query_embedding}' as distance
        FROM #{@schema}.embeddings
        ORDER BY distance
        LIMIT #{limit}
      SQL
      
      results.map(&:to_h)
    end
  end
end
```

### 4. Redis Namespace Isolation

```ruby
# app/services/cache/ekn_cache.rb
module Cache
  class EknCache
    def initialize(ekn)
      @ekn = ekn
      @redis = Redis.new(url: ENV['REDIS_URL'])
      @namespace = "ekn:#{ekn.id}"
    end
    
    def get(key)
      @redis.get("#{@namespace}:#{key}")
    end
    
    def set(key, value, ex: 3600)
      @redis.set("#{@namespace}:#{key}", value, ex: ex)
    end
    
    def delete_all!
      # Delete all keys for this EKN
      cursor = "0"
      loop do
        cursor, keys = @redis.scan(cursor, match: "#{@namespace}:*")
        @redis.del(*keys) if keys.any?
        break if cursor == "0"
      end
    end
  end
end
```

### 5. Unified EKN Manager

```ruby
# app/services/ekn_manager.rb
class EknManager
  def self.create_ekn(name:, description: nil)
    ActiveRecord::Base.transaction do
      # Create the IngestBatch record
      ekn = IngestBatch.create!(
        name: name,
        description: description,
        status: 'initializing'
      )
      
      # Create all isolated resources
      ekn.ensure_neo4j_database_exists!
      ekn.ensure_postgres_schema_exists!
      
      storage = Storage::EknStorage.new(ekn)
      storage.ensure_storage_exists!
      
      ekn.update!(status: 'ready')
      
      Rails.logger.info "Created EKN #{ekn.id} with complete isolation"
      ekn
    end
  end
  
  def self.destroy_ekn(ekn)
    Rails.logger.info "Destroying EKN #{ekn.id} and all associated data..."
    
    # Delete from all stores
    ekn.drop_neo4j_database!
    ekn.drop_postgres_schema!
    
    Storage::EknStorage.new(ekn).destroy_all_storage!
    Cache::EknCache.new(ekn).delete_all!
    
    # Finally delete the record
    ekn.destroy!
    
    Rails.logger.info "Successfully destroyed EKN #{ekn.id}"
  end
  
  def self.backup_ekn(ekn, destination)
    # Backup all data sources
    backup_path = "#{destination}/ekn_#{ekn.id}_#{Time.now.to_i}"
    
    # Neo4j backup
    system("neo4j-admin database dump #{ekn.neo4j_database_name} --to-path=#{backup_path}/neo4j")
    
    # PostgreSQL backup
    system("pg_dump -n #{ekn.postgres_schema_name} > #{backup_path}/postgres.sql")
    
    # Files backup
    if Storage::EknStorage.new(ekn).storage_type == 'filesystem'
      system("tar -czf #{backup_path}/files.tar.gz #{ekn.root_path}")
    end
    
    Rails.logger.info "Backed up EKN #{ekn.id} to #{backup_path}"
    backup_path
  end
end
```

## Migration Path

### Phase 1: New EKNs (Immediate)
- All new EKNs use complete isolation
- Update pipeline to use isolated resources

### Phase 2: Existing Data Migration (Week 1)
```ruby
# lib/tasks/migrate_to_isolated_ekns.rake
namespace :ekn do
  task migrate_existing: :environment do
    IngestBatch.find_each do |ekn|
      puts "Migrating EKN #{ekn.id}: #{ekn.name}"
      
      # Create isolated resources
      ekn.ensure_neo4j_database_exists!
      ekn.ensure_postgres_schema_exists!
      
      # Migrate Neo4j data
      Graph::QueryService.new(nil).session do |source|
        Graph::QueryService.new(ekn.neo4j_database_name).session do |target|
          # Copy nodes and relationships filtered by batch_id
        end
      end
      
      # Migrate PostgreSQL data
      ApplicationRecord.connection.execute(<<-SQL)
        INSERT INTO #{ekn.postgres_schema_name}.embeddings
        SELECT * FROM embeddings WHERE batch_id = #{ekn.id};
        
        INSERT INTO #{ekn.postgres_schema_name}.documents
        SELECT * FROM documents WHERE batch_id = #{ekn.id};
      SQL
      
      # Migrate files
      # ... file migration logic
    end
  end
end
```

## Security Benefits

1. **Data Isolation**: No cross-contamination possible
2. **Access Control**: Can grant database-level permissions
3. **Audit Trail**: Clear boundaries for audit logs
4. **Compliance**: GDPR/HIPAA data residency requirements
5. **Clean Deletion**: Complete data removal with DROP commands

## Performance Benefits

1. **Independent Scaling**: Large EKNs can be moved to dedicated infrastructure
2. **No Lock Contention**: Each EKN has its own locks
3. **Optimized Indexes**: Each EKN can have custom indexes
4. **Cache Isolation**: No cache pollution between EKNs

## Cost Analysis

### Shared Infrastructure (Recommended)
- 1 PostgreSQL instance: $100/month
- 1 Neo4j instance: $200/month  
- 1 Redis instance: $50/month
- Storage: $0.023/GB/month
- **Total for 100 EKNs: ~$350/month + storage**

### Docker Compose per EKN
- 100 PostgreSQL containers: $2000/month
- 100 Neo4j containers: $5000/month
- 100 Redis containers: $1000/month
- Orchestration overhead: $1000/month
- **Total for 100 EKNs: ~$9000/month + storage**

## Decision: Hybrid Isolation

**Use shared infrastructure with logical isolation:**
- PostgreSQL schemas for SQL data
- Neo4j databases for graph data
- Filesystem/S3 prefixes for files
- Redis namespaces for cache

This provides:
- ✅ Complete data isolation
- ✅ Cost efficiency
- ✅ Manageable complexity
- ✅ Production scalability
- ✅ Easy backup/restore
- ✅ Clean deletion

## Implementation Checklist

- [ ] Create EknManager service
- [ ] Update IngestBatch model with schema methods
- [ ] Create Storage::EknStorage service
- [ ] Update Embedding services for schema awareness
- [ ] Create Cache::EknCache for Redis isolation
- [ ] Update Graph::QueryService to use database parameter
- [ ] Migrate existing data to isolated schemas
- [ ] Update all pipeline stages for isolation
- [ ] Add monitoring for resource usage per EKN
- [ ] Create backup/restore rake tasks
- [ ] Document operations procedures