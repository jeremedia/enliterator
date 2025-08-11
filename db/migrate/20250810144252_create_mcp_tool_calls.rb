class CreateMcpToolCalls < ActiveRecord::Migration[8.0]
  def change
    create_table :mcp_tool_calls do |t|
      t.references :ekn, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: true
      t.references :message, null: false, foreign_key: true
      t.string :tool_name
      t.string :tool_id
      t.jsonb :arguments
      t.jsonb :request_data
      t.jsonb :response_data
      t.string :status
      t.datetime :started_at
      t.datetime :completed_at
      t.text :error_message
      t.string :server_label

      t.timestamps
    end
  end
end
