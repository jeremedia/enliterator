class CreateSymbolics < ActiveRecord::Migration[8.0]
  def change
    create_table :symbolics do |t|
      t.string :label
      t.string :symbol_type
      t.text :meaning
      t.text :cultural_context
      t.datetime :valid_time_start
      t.text :repr_text
      t.references :provenance_and_rights, null: false, foreign_key: true
      t.integer :batch_id
      t.string :entity_id

      t.timestamps
    end
  end
end
