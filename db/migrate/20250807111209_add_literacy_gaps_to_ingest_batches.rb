class AddLiteracyGapsToIngestBatches < ActiveRecord::Migration[8.0]
  def change
    add_column :ingest_batches, :literacy_gaps, :jsonb
  end
end
