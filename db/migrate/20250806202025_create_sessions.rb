class CreateSessions < ActiveRecord::Migration[8.0]
  def change
    create_table :sessions do |t|
      t.string :browser_session_id, null: false
      t.jsonb :metadata, default: {}
      t.timestamps
    end
    
    add_index :sessions, :browser_session_id, unique: true
  end
end
