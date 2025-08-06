class CreateMessages < ActiveRecord::Migration[8.0]
  def change
    create_table :messages do |t|
      t.references :conversation, null: false, foreign_key: true
      t.integer :role
      t.text :content
      t.jsonb :metadata
      t.integer :tokens_used

      t.timestamps
    end
  end
end
