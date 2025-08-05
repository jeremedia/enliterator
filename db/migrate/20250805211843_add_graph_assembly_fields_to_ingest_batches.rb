class AddGraphAssemblyFieldsToIngestBatches < ActiveRecord::Migration[8.0]
  def change
    add_column :ingest_batches, :graph_assembly_stats, :jsonb
    add_column :ingest_batches, :graph_assembled_at, :datetime
  end
end
