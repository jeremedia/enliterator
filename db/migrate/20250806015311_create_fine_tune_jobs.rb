class CreateFineTuneJobs < ActiveRecord::Migration[8.0]
  def change
    create_table :fine_tune_jobs do |t|
      t.string :openai_job_id, null: false
      t.string :openai_file_id
      t.string :base_model, null: false
      t.string :fine_tuned_model # Available after completion
      t.string :status, null: false # 'validating_files', 'queued', 'running', 'succeeded', 'failed', 'cancelled'
      t.jsonb :hyperparameters, default: {}
      t.jsonb :training_metrics, default: {}
      t.integer :trained_tokens
      t.decimal :training_cost, precision: 10, scale: 4
      t.datetime :started_at
      t.datetime :finished_at
      t.text :error_message
      t.bigint :ingest_batch_id
      t.string :dataset_path
      t.integer :example_count
      
      t.timestamps
    end
    
    add_index :fine_tune_jobs, :openai_job_id, unique: true
    add_index :fine_tune_jobs, :status
    add_index :fine_tune_jobs, :fine_tuned_model
    add_index :fine_tune_jobs, :ingest_batch_id
  end
end
