# frozen_string_literal: true

class CreateIngestItems < ActiveRecord::Migration[8.0]
  def change
    create_table :ingest_items do |t|
      t.references :ingest_batch, null: false, foreign_key: true
      t.references :provenance_and_rights, foreign_key: true
      
      # Polymorphic association for pool items
      t.references :pool_item, polymorphic: true
      
      t.string :source_hash, null: false
      t.string :file_path, null: false
      t.string :source_type
      t.string :media_type, null: false, default: 'unknown'
      t.string :triage_status, null: false, default: 'pending'
      
      t.bigint :size_bytes
      t.text :content_sample, limit: 5000
      t.jsonb :metadata, default: {}
      t.jsonb :triage_metadata, default: {}
      t.string :triage_error
      
      t.timestamps
    end
    
    add_index :ingest_items, :source_hash, unique: true
    add_index :ingest_items, :triage_status
    add_index :ingest_items, :media_type
    add_index :ingest_items, [:pool_item_type, :pool_item_id]
  end
end
