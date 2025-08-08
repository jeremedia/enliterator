class AddRightsFieldsToIngestItems < ActiveRecord::Migration[8.0]
  def change
    add_column :ingest_items, :training_eligible, :boolean
    add_column :ingest_items, :publishable, :boolean
    add_column :ingest_items, :quarantined, :boolean
    add_column :ingest_items, :quarantine_reason, :string
    add_column :ingest_items, :file_hash, :string
    add_column :ingest_items, :file_size, :integer
  end
end
