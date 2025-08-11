class CreateSpaces < ActiveRecord::Migration[8.0]
  def change
    create_table :spaces do |t|
      t.string :label
      t.string :spatial_type
      t.string :region
      t.string :country
      t.decimal :latitude
      t.decimal :longitude
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
