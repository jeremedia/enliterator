class AddExternalCallSupportToMcpToolCalls < ActiveRecord::Migration[8.0]
  def change
    # Allow null conversation_id and message_id for external calls (OpenAI Playground, etc.)
    change_column_null :mcp_tool_calls, :conversation_id, true
    change_column_null :mcp_tool_calls, :message_id, true
    
    # Add external call tracking fields
    add_column :mcp_tool_calls, :client_name, :string
    add_column :mcp_tool_calls, :client_version, :string  
    add_column :mcp_tool_calls, :client_ip, :string
    add_column :mcp_tool_calls, :is_external_call, :boolean, default: false, null: false
    
    # Add indexes for efficient querying
    add_index :mcp_tool_calls, :is_external_call
    add_index :mcp_tool_calls, [:client_name, :created_at]
  end
end
