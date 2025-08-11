class CreateRelators < ActiveRecord::Migration[8.0]
  def change
    create_table :relators do |t|
      t.string :label
      t.string :relation_type
      t.string :source_label
      t.string :target_label
      t.decimal :strength
      t.boolean :bidirectional
      t.text :description
      t.datetime :valid_time_start
      t.text :repr_text
      t.references :provenance_and_rights, null: false, foreign_key: true
      t.integer :batch_id
      t.string :entity_id

      t.timestamps
    end
  end
end
