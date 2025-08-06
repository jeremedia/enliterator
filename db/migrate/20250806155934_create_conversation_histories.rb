class CreateConversationHistories < ActiveRecord::Migration[8.0]
  def change
    create_table :conversation_histories do |t|
      t.string :conversation_id
      t.string :user_id
      t.string :role
      t.text :content
      t.jsonb :metadata
      t.integer :position

      t.timestamps
    end
    add_index :conversation_histories, :conversation_id
  end
end
