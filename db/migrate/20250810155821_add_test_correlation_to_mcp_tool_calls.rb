class AddTestCorrelationToMcpToolCalls < ActiveRecord::Migration[8.0]
  def change
    # Link tool calls to test executions for correlation (null for non-test calls)
    add_reference :mcp_tool_calls, :mcp_test_execution, null: true, foreign_key: true
    
    # Track OpenAI request IDs for correlation across the pipeline
    add_column :mcp_tool_calls, :openai_request_id, :string
    
    add_index :mcp_tool_calls, :openai_request_id
    # Note: add_reference already creates the mcp_test_execution_id index automatically
  end
end
