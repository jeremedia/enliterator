class AddLiteracyScoreToIngestBatches < ActiveRecord::Migration[8.0]
  def change
    add_column :ingest_batches, :literacy_score, :decimal
  end
end
