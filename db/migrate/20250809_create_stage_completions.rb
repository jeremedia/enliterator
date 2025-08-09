# frozen_string_literal: true

class CreateStageCompletions < ActiveRecord::Migration[8.0]
  def change
    create_table :stage_completions do |t|
      t.references :ingest_batch, null: false, foreign_key: true
      t.references :ekn, null: false, foreign_key: true
      t.integer :stage_number, null: false
      t.string :stage_name, null: false
      t.string :status, null: false, default: 'pending'
      # pending, checking, skipped, in_progress, completed, failed
      
      # Metrics to determine if stage can be skipped
      t.jsonb :completion_metrics, default: {}
      # e.g., {
      #   entities_extracted: 1000,
      #   items_processed: 1000,
      #   coverage_rate: 0.95,
      #   pools_filled: ["Idea", "Practical", "Experience"]
      # }
      
      # Fingerprint of stage output for change detection
      t.string :output_fingerprint
      
      # Why was it skipped?
      t.text :skip_reason
      
      # Timing
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :checked_at
      
      # Cost tracking for expensive stages
      t.decimal :api_cost_usd, precision: 10, scale: 4
      t.integer :api_calls_made
      
      t.timestamps
      
      t.index [:ingest_batch_id, :stage_number], unique: true
      t.index [:ekn_id, :stage_number]
      t.index :status
    end
  end
end