class AddIngestBatchIdToProvenanceAndRights < ActiveRecord::Migration[8.0]
  def change
    # Step 1: Add column as nullable to handle existing records
    add_reference :provenance_and_rights, :ingest_batch, null: true, foreign_key: true
    
    # Step 2: Backfill existing records to Arctic Navigator (Batch #1)
    reversible do |dir|
      dir.up do
        # Connect all existing provenance records to Arctic Navigator batch
        arctic_batch = IngestBatch.find_by(name: "Arctic Research Documents Collection")
        if arctic_batch
          ProvenanceAndRights.where(ingest_batch_id: nil).update_all(ingest_batch_id: arctic_batch.id)
          puts "✅ Connected #{ProvenanceAndRights.count} existing provenance records to Arctic Navigator (Batch ##{arctic_batch.id})"
        else
          puts "⚠️  Arctic Navigator batch not found - manual backfill required"
        end
      end
    end
    
    # Step 3: Make column non-nullable now that all records have values
    change_column_null :provenance_and_rights, :ingest_batch_id, false
  end
end
