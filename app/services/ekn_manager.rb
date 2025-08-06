# Manages the lifecycle of Enliterated Knowledge Navigators (EKNs)
# Handles creation, deletion, backup, and restoration with complete data isolation
#
# Each EKN is a completely isolated knowledge domain with:
# - Its own Neo4j database
# - Its own PostgreSQL schema
# - Its own file storage directory
# - Its own Redis namespace
#
class EknManager
  class << self
    def create_ekn(name:, description: nil, source_type: 'upload')
      ActiveRecord::Base.transaction do
        Rails.logger.info "Creating new EKN: #{name}"
        
        # Create the IngestBatch record
        ekn = IngestBatch.create!(
          name: name,
          source_type: source_type,
          status: :pending,
          metadata: {
            description: description,
            created_by: 'EknManager',
            isolation_enabled: true,
            created_at: Time.current
          }
        )
        
        # Create all isolated resources
        Rails.logger.info "Creating isolated resources for EKN #{ekn.id}"
        
        begin
          # Neo4j database
          ekn.ensure_neo4j_database_exists!
          Rails.logger.info "✓ Created Neo4j database: #{ekn.neo4j_database_name}"
          
          # PostgreSQL schema
          ekn.ensure_postgres_schema_exists!
          Rails.logger.info "✓ Created PostgreSQL schema: #{ekn.postgres_schema_name}"
          
          # File storage
          ekn.ensure_storage_exists!
          Rails.logger.info "✓ Created storage directory: #{ekn.storage_root_path}"
          
          # Update status
          ekn.update!(
            status: :intake_in_progress,
            metadata: ekn.metadata.merge(
              resources_created: true,
              neo4j_database: ekn.neo4j_database_name,
              postgres_schema: ekn.postgres_schema_name,
              storage_path: ekn.storage_root_path.to_s
            )
          )
          
          Rails.logger.info "Successfully created EKN #{ekn.id}: #{ekn.name}"
          ekn
        rescue => e
          Rails.logger.error "Failed to create resources for EKN #{ekn.id}: #{e.message}"
          
          # Clean up any partially created resources
          cleanup_partial_resources(ekn)
          
          # Mark as failed
          ekn.update!(status: :failed)
          
          raise
        end
      end
    end
    
    def destroy_ekn(ekn)
      Rails.logger.info "Destroying EKN #{ekn.id}: #{ekn.name}"
      
      begin
        # Delete Neo4j database
        ekn.drop_neo4j_database!
        Rails.logger.info "✓ Deleted Neo4j database"
      rescue => e
        Rails.logger.error "Failed to delete Neo4j database: #{e.message}"
      end
      
      begin
        # Delete PostgreSQL schema
        ekn.drop_postgres_schema!
        Rails.logger.info "✓ Deleted PostgreSQL schema"
      rescue => e
        Rails.logger.error "Failed to delete PostgreSQL schema: #{e.message}"
      end
      
      begin
        # Delete file storage
        ekn.drop_all_storage!
        Rails.logger.info "✓ Deleted file storage"
      rescue => e
        Rails.logger.error "Failed to delete file storage: #{e.message}"
      end
      
      begin
        # Delete Redis cache
        clear_redis_cache(ekn)
        Rails.logger.info "✓ Cleared Redis cache"
      rescue => e
        Rails.logger.error "Failed to clear Redis cache: #{e.message}"
      end
      
      # Finally delete the record
      ekn.destroy!
      
      Rails.logger.info "Successfully destroyed EKN #{ekn.id}"
      true
    end
    
    def backup_ekn(ekn, destination_dir = nil)
      destination_dir ||= Rails.root.join('backups')
      FileUtils.mkdir_p(destination_dir)
      
      timestamp = Time.current.strftime('%Y%m%d_%H%M%S')
      backup_name = "ekn_#{ekn.id}_#{ekn.name.parameterize}_#{timestamp}"
      backup_path = File.join(destination_dir, backup_name)
      FileUtils.mkdir_p(backup_path)
      
      Rails.logger.info "Backing up EKN #{ekn.id} to #{backup_path}"
      
      # Create metadata file
      File.write(
        File.join(backup_path, 'metadata.json'),
        {
          ekn_id: ekn.id,
          name: ekn.name,
          description: ekn.metadata&.dig('description'),
          created_at: ekn.created_at,
          backed_up_at: Time.current,
          neo4j_database: ekn.neo4j_database_name,
          postgres_schema: ekn.postgres_schema_name,
          statistics: ekn.statistics
        }.to_json
      )
      
      # Backup Neo4j database
      neo4j_backup_path = File.join(backup_path, 'neo4j.dump')
      backup_neo4j(ekn, neo4j_backup_path)
      
      # Backup PostgreSQL schema
      postgres_backup_path = File.join(backup_path, 'postgres.sql')
      backup_postgres(ekn, postgres_backup_path)
      
      # Backup files if using filesystem storage
      if ENV.fetch('STORAGE_TYPE', 'filesystem') == 'filesystem'
        files_backup_path = File.join(backup_path, 'files.tar.gz')
        backup_files(ekn, files_backup_path)
      end
      
      Rails.logger.info "Successfully backed up EKN #{ekn.id} to #{backup_path}"
      backup_path
    end
    
    def restore_ekn(backup_path, new_name: nil)
      unless File.exist?(backup_path)
        raise ArgumentError, "Backup path does not exist: #{backup_path}"
      end
      
      metadata_path = File.join(backup_path, 'metadata.json')
      unless File.exist?(metadata_path)
        raise ArgumentError, "Invalid backup: missing metadata.json"
      end
      
      metadata = JSON.parse(File.read(metadata_path))
      
      # Create new EKN
      ekn = create_ekn(
        name: new_name || "#{metadata['name']} (Restored)",
        description: "Restored from backup: #{metadata['backed_up_at']}"
      )
      
      Rails.logger.info "Restoring EKN from backup to new EKN #{ekn.id}"
      
      # Restore Neo4j data
      neo4j_backup = File.join(backup_path, 'neo4j.dump')
      if File.exist?(neo4j_backup)
        restore_neo4j(ekn, neo4j_backup)
      end
      
      # Restore PostgreSQL data
      postgres_backup = File.join(backup_path, 'postgres.sql')
      if File.exist?(postgres_backup)
        restore_postgres(ekn, postgres_backup)
      end
      
      # Restore files
      files_backup = File.join(backup_path, 'files.tar.gz')
      if File.exist?(files_backup)
        restore_files(ekn, files_backup)
      end
      
      ekn.update!(status: :completed)
      
      Rails.logger.info "Successfully restored EKN #{ekn.id}"
      ekn
    end
    
    def list_ekns
      IngestBatch.includes(:ingest_items).map do |ekn|
        {
          id: ekn.id,
          name: ekn.name,
          description: ekn.metadata&.dig('description'),
          status: ekn.status,
          created_at: ekn.created_at,
          item_count: ekn.ingest_items.count,
          neo4j_database: ekn.neo4j_database_name,
          postgres_schema: ekn.postgres_schema_name,
          storage_path: ekn.storage_root_path.to_s
        }
      end
    end
    
    def ekn_statistics(ekn)
      stats = {
        ekn_id: ekn.id,
        name: ekn.name,
        status: ekn.status
      }
      
      # Neo4j statistics
      begin
        graph_stats = Graph::DatabaseManager.get_database_statistics(ekn.neo4j_database_name)
        stats[:neo4j] = graph_stats
      rescue => e
        stats[:neo4j] = { error: e.message }
      end
      
      # PostgreSQL statistics
      begin
        schema = ekn.postgres_schema_name
        result = ApplicationRecord.connection.execute(<<-SQL)
          SELECT 
            (SELECT COUNT(*) FROM #{schema}.embeddings) as embedding_count,
            (SELECT COUNT(*) FROM #{schema}.documents) as document_count,
            (SELECT COUNT(*) FROM #{schema}.entities) as entity_count,
            (SELECT COUNT(*) FROM #{schema}.lexicon_entries) as lexicon_count
        SQL
        
        row = result.first
        stats[:postgres] = {
          embeddings: row['embedding_count'],
          documents: row['document_count'],
          entities: row['entity_count'],
          lexicon_entries: row['lexicon_count']
        }
      rescue => e
        stats[:postgres] = { error: e.message }
      end
      
      # File storage statistics
      if ENV.fetch('STORAGE_TYPE', 'filesystem') == 'filesystem'
        path = ekn.storage_root_path
        if File.exist?(path)
          stats[:storage] = {
            path: path.to_s,
            size_bytes: Dir.glob(File.join(path, '**', '*')).sum { |f| File.size(f) rescue 0 },
            file_count: Dir.glob(File.join(path, '**', '*')).count { |f| File.file?(f) }
          }
        end
      end
      
      stats
    end
    
    private
    
    def cleanup_partial_resources(ekn)
      Rails.logger.info "Cleaning up partial resources for EKN #{ekn.id}"
      
      begin
        ekn.drop_neo4j_database!
      rescue => e
        Rails.logger.debug "Neo4j cleanup: #{e.message}"
      end
      
      begin
        ekn.drop_postgres_schema!
      rescue => e
        Rails.logger.debug "PostgreSQL cleanup: #{e.message}"
      end
      
      begin
        ekn.drop_all_storage!
      rescue => e
        Rails.logger.debug "Storage cleanup: #{e.message}"
      end
    end
    
    def clear_redis_cache(ekn)
      redis = Redis.new(url: ENV['REDIS_URL'])
      namespace = "ekn:#{ekn.id}"
      
      cursor = "0"
      loop do
        cursor, keys = redis.scan(cursor, match: "#{namespace}:*", count: 100)
        redis.del(*keys) if keys.any?
        break if cursor == "0"
      end
    end
    
    def backup_neo4j(ekn, destination)
      # Using neo4j-admin for backup
      # Note: This requires neo4j-admin to be available in PATH
      system("neo4j-admin database dump #{ekn.neo4j_database_name} --to-path=#{File.dirname(destination)}")
      
      # Rename the dump file
      expected_dump = File.join(File.dirname(destination), "#{ekn.neo4j_database_name}.dump")
      if File.exist?(expected_dump)
        FileUtils.mv(expected_dump, destination)
      end
    rescue => e
      Rails.logger.error "Neo4j backup failed: #{e.message}"
      # Fallback: Export as Cypher statements
      # This would require implementing a Cypher export
    end
    
    def backup_postgres(ekn, destination)
      schema = ekn.postgres_schema_name
      
      # Use pg_dump to backup the schema
      system("pg_dump -n #{schema} -f #{destination} #{ENV['DATABASE_URL']}")
    rescue => e
      Rails.logger.error "PostgreSQL backup failed: #{e.message}"
    end
    
    def backup_files(ekn, destination)
      source = ekn.storage_root_path
      if File.exist?(source)
        system("tar -czf #{destination} -C #{File.dirname(source)} #{File.basename(source)}")
      end
    rescue => e
      Rails.logger.error "File backup failed: #{e.message}"
    end
    
    def restore_neo4j(ekn, source)
      # Use neo4j-admin to restore
      system("neo4j-admin database load #{ekn.neo4j_database_name} --from-path=#{File.dirname(source)}")
    rescue => e
      Rails.logger.error "Neo4j restore failed: #{e.message}"
    end
    
    def restore_postgres(ekn, source)
      # Restore the schema
      system("psql #{ENV['DATABASE_URL']} < #{source}")
    rescue => e
      Rails.logger.error "PostgreSQL restore failed: #{e.message}"
    end
    
    def restore_files(ekn, source)
      destination = ekn.storage_root_path
      FileUtils.mkdir_p(destination)
      system("tar -xzf #{source} -C #{File.dirname(destination)}")
    rescue => e
      Rails.logger.error "File restore failed: #{e.message}"
    end
  end
end