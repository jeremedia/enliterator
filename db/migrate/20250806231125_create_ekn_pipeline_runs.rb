class CreateEknPipelineRuns < ActiveRecord::Migration[8.0]
  def change
    create_table :ekn_pipeline_runs do |t|
      t.references :ekn, null: false, foreign_key: true
      t.references :ingest_batch, null: false, foreign_key: true
      
      # State machine
      t.string :status, null: false, default: 'initialized'
      t.string :current_stage
      t.integer :current_stage_number, default: 0
      
      # Progress tracking
      t.jsonb :stage_statuses, default: {}
      t.jsonb :stage_metrics, default: {}
      t.datetime :stage_started_at
      t.datetime :stage_completed_at
      
      # Overall metrics
      t.datetime :started_at
      t.datetime :completed_at
      t.integer :total_items_processed, default: 0
      t.integer :total_nodes_created, default: 0
      t.integer :total_relationships_created, default: 0
      t.float :literacy_score
      
      # Error handling
      t.string :failed_stage
      t.text :error_message
      t.jsonb :error_details, default: {}
      t.integer :retry_count, default: 0
      t.datetime :last_retry_at
      
      # Configuration
      t.jsonb :options, default: {}
      t.boolean :auto_advance, default: true
      t.boolean :skip_failed_items, default: false
      
      t.timestamps
    end
    
    add_index :ekn_pipeline_runs, :status
    add_index :ekn_pipeline_runs, :current_stage
    add_index :ekn_pipeline_runs, [:ekn_id, :status]
    add_index :ekn_pipeline_runs, [:ekn_id, :created_at]
  end
end