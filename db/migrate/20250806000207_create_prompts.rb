class CreatePrompts < ActiveRecord::Migration[8.0]
  def change
    create_table :prompts do |t|
      t.string :key
      t.string :name
      t.text :description
      t.integer :category
      t.integer :context
      t.boolean :active
      t.integer :current_version_id

      t.timestamps
    end
    add_index :prompts, :key, unique: true
  end
end
