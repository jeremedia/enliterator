class CreateLifecycles < ActiveRecord::Migration[8.0]
  def change
    create_table :lifecycles do |t|
      t.string :label
      t.string :stage_type
      t.integer :sequence_order
      t.boolean :is_active
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
