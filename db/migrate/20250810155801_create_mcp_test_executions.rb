class CreateMcpTestExecutions < ActiveRecord::Migration[8.0]
  def change
    create_table :mcp_test_executions do |t|
      t.references :mcp_test_run, null: false, foreign_key: true
      t.references :mcp_test_case, null: false, foreign_key: true
      t.integer :status, default: 0, null: false  # enum: pending: 0, running: 1, completed: 2, failed: 3
      t.datetime :started_at
      t.datetime :completed_at
      t.json :execution_metrics   # {"response_time_ms": 2340, "tools_called_count": 3}
      t.json :assertion_results   # {"correct_tools_called": true, "response_quality_score": 0.87}
      t.text :error_message

      t.timestamps
    end
    
    add_index :mcp_test_executions, :status
    add_index :mcp_test_executions, [:mcp_test_run_id, :mcp_test_case_id], unique: true, name: 'idx_mcp_test_exec_unique'
    add_index :mcp_test_executions, :started_at
  end
end
