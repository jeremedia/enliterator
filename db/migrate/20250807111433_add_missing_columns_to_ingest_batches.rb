class AddMissingColumnsToIngestBatches < ActiveRecord::Migration[8.0]
  def change
    add_column :ingest_batches, :deliverables, :jsonb
  end
end
