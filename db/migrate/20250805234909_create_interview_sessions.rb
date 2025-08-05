class CreateInterviewSessions < ActiveRecord::Migration[8.0]
  def change
    create_table :interview_sessions do |t|
      t.string :session_id
      t.jsonb :data
      t.boolean :completed

      t.timestamps
    end
    add_index :interview_sessions, :session_id
  end
end
