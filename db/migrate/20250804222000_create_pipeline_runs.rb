# frozen_string_literal: true

class CreatePipelineRuns < ActiveRecord::Migration[8.0]
  def change
    create_table :pipeline_runs do |t|
      t.string :bundle_path, null: false
      t.string :stage, null: false
      t.string :status, null: false
      t.datetime :started_at, null: false
      t.datetime :completed_at
      t.jsonb :metrics, default: {}
      t.jsonb :options, default: {}
      t.integer :file_count
      t.text :error_message
      
      t.timestamps
    end
    
    create_table :pipeline_artifacts do |t|
      t.references :pipeline_run, null: false, foreign_key: true
      t.string :artifact_type, null: false
      t.string :file_path, null: false
      t.jsonb :metadata, default: {}
      
      t.timestamps
    end
    
    create_table :pipeline_errors do |t|
      t.references :pipeline_run, null: false, foreign_key: true
      t.string :stage, null: false
      t.string :error_type, null: false
      t.text :message
      t.datetime :occurred_at, null: false
      
      t.timestamps
    end
    
    # Indexes
    add_index :pipeline_runs, :status
    add_index :pipeline_runs, :stage
    add_index :pipeline_runs, :started_at
    add_index :pipeline_runs, [:stage, :status]
    
    add_index :pipeline_artifacts, :artifact_type
    add_index :pipeline_errors, :stage
  end
end