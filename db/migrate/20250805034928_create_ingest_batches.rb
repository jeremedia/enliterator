# frozen_string_literal: true

class CreateIngestBatches < ActiveRecord::Migration[8.0]
  def change
    create_table :ingest_batches do |t|
      t.string :name, null: false
      t.string :source_type, null: false
      t.integer :status, default: 0, null: false
      t.jsonb :metadata, default: {}
      t.jsonb :statistics, default: {}
      t.datetime :started_at
      t.datetime :completed_at
      
      t.timestamps
    end
    
    add_index :ingest_batches, :status
    add_index :ingest_batches, :source_type
    add_index :ingest_batches, :created_at
  end
end
