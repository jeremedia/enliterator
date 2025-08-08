class AddFineTuneColumnsToIngestBatches < ActiveRecord::Migration[8.0]
  def change
    add_column :ingest_batches, :fine_tune_dataset_path, :string
    add_column :ingest_batches, :fine_tune_job_id, :string
  end
end
