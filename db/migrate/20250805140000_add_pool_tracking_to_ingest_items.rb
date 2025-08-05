# frozen_string_literal: true

class AddPoolTrackingToIngestItems < ActiveRecord::Migration[8.0]
  def change
    add_column :ingest_items, :pool_status, :string, default: 'pending'
    add_column :ingest_items, :pool_metadata, :jsonb, default: {}
    
    add_index :ingest_items, :pool_status
  end
end