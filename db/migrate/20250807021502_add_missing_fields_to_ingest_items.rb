class AddMissingFieldsToIngestItems < ActiveRecord::Migration[8.0]
  def change
    add_column :ingest_items, :graph_status, :string
    add_column :ingest_items, :graph_metadata, :jsonb
    add_column :ingest_items, :embedding_status, :string
    add_column :ingest_items, :embedding_metadata, :jsonb
  end
end
