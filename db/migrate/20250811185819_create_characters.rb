class CreateCharacters < ActiveRecord::Migration[8.0]
  def change
    create_table :characters do |t|
      t.string :label
      t.string :role_type
      t.string :title
      t.text :biography
      t.boolean :active
      t.boolean :has_agency
      t.datetime :valid_time_start
      t.text :repr_text
      t.references :provenance_and_rights, null: false, foreign_key: true
      t.integer :batch_id
      t.string :entity_id

      t.timestamps
    end
  end
end
