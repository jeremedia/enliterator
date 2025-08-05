# frozen_string_literal: true

class AddLexiconTrackingToIngestItems < ActiveRecord::Migration[7.2]
  def change
    # Add lexicon extraction tracking columns
    add_column :ingest_items, :lexicon_status, :string, default: 'pending'
    add_column :ingest_items, :lexicon_metadata, :jsonb, default: {}
    add_column :ingest_items, :content, :text
    
    # Add indexes for efficient querying
    add_index :ingest_items, :lexicon_status
    
    # Also ensure IngestBatch has the lexicon status values we use
    reversible do |dir|
      dir.up do
        # Add new status values to IngestBatch enum if needed
        execute <<-SQL
          ALTER TABLE ingest_batches 
          ADD CONSTRAINT check_status_values 
          CHECK (status IN (0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20))
        SQL
      end
      
      dir.down do
        execute <<-SQL
          ALTER TABLE ingest_batches DROP CONSTRAINT IF EXISTS check_status_values
        SQL
      end
    end
  end
end