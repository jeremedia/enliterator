class AddDeliverablesFieldsToIngestBatches < ActiveRecord::Migration[8.0]
  def change
    add_column :ingest_batches, :deliverables_generated_at, :datetime
    add_column :ingest_batches, :deliverables_path, :string
    add_column :ingest_batches, :deliverables_errors, :text
  end
end
