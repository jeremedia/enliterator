class AddEknToIngestBatches < ActiveRecord::Migration[8.0]
  def change
    # Add foreign key to ingest_batches
    add_reference :ingest_batches, :ekn, foreign_key: true
    
    # Migrate existing batches to become EKNs
    reversible do |dir|
      dir.up do
        # Create EKNs for existing IngestBatches
        execute <<-SQL
          INSERT INTO ekns (name, description, status, domain_type, personality, metadata, created_at, updated_at)
          SELECT 
            COALESCE(name, 'Migrated Dataset ' || id::text) as name,
            'Migrated from IngestBatch #' || id::text as description,
            CASE 
              WHEN status = 19 THEN 'active'  -- completed
              WHEN status IN (3, 7, 20) THEN 'failed'  -- various failed states
              ELSE 'initializing'
            END as status,
            'general' as domain_type,
            'friendly' as personality,
            jsonb_build_object(
              'migrated_from_batch_id', id,
              'original_source_type', source_type,
              'original_metadata', metadata
            ) as metadata,
            created_at,
            updated_at
          FROM ingest_batches
          WHERE ekn_id IS NULL;
        SQL
        
        # Link batches to their new EKNs
        execute <<-SQL
          UPDATE ingest_batches b
          SET ekn_id = e.id
          FROM ekns e
          WHERE e.metadata->>'migrated_from_batch_id' = b.id::text
            AND b.ekn_id IS NULL;
        SQL
        
        # Rename Neo4j databases if they exist
        # This would need to be done via Neo4j connection
        Rails.logger.info "Migration complete. Neo4j databases may need renaming from ekn-{batch_id} to ekn_{ekn_id}"
      end
      
      dir.down do
        # Remove the ekn_id from batches
        execute "UPDATE ingest_batches SET ekn_id = NULL"
        
        # Delete migrated EKNs
        execute "DELETE FROM ekns WHERE metadata->>'migrated_from_batch_id' IS NOT NULL"
      end
    end
  end
end
