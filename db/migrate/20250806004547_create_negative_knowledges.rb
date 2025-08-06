class CreateNegativeKnowledges < ActiveRecord::Migration[8.0]
  def change
    create_table :negative_knowledges do |t|
      t.references :batch, null: true, foreign_key: { to_table: :ingest_batches }
      t.string :gap_type
      t.text :gap_description
      t.string :severity
      t.text :affected_pools
      t.text :impact
      t.text :suggested_remediation
      t.jsonb :metadata

      t.timestamps
    end
  end
end
