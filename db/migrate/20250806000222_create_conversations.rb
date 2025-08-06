class CreateConversations < ActiveRecord::Migration[8.0]
  def change
    create_table :conversations do |t|
      t.references :user, foreign_key: true, null: true
      t.references :ingest_batch, foreign_key: true, null: true
      t.jsonb :context, default: {}
      t.jsonb :model_config, default: {}  # CRITICAL: Stores model configuration
      t.string :status
      t.string :expertise_level
      t.datetime :last_activity_at
      
      t.timestamps
    end
    
    add_index :conversations, :status
    add_index :conversations, :last_activity_at
  end
end
