class CreateTimeEntities < ActiveRecord::Migration[8.0]
  def change
    create_table :time_entities do |t|
      t.string :label
      t.string :temporal_type
      t.text :description
      t.datetime :start_time
      t.datetime :end_time
      t.boolean :recurring
      t.datetime :valid_time_start
      t.text :repr_text
      t.references :provenance_and_rights, null: false, foreign_key: true
      t.integer :batch_id
      t.string :entity_id

      t.timestamps
    end
  end
end
