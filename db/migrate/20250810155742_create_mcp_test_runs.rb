class CreateMcpTestRuns < ActiveRecord::Migration[8.0]
  def change
    create_table :mcp_test_runs do |t|
      t.references :mcp_test_suite, null: false, foreign_key: true
      t.integer :status, default: 0, null: false  # enum: pending: 0, running: 1, completed: 2, failed: 3
      t.datetime :started_at
      t.datetime :completed_at
      t.json :summary_metrics  # {"total_cases": 12, "passed": 10, "avg_response_time": 2340}
      t.text :error_message

      t.timestamps
    end
    
    add_index :mcp_test_runs, :status
    add_index :mcp_test_runs, [:mcp_test_suite_id, :created_at]
    add_index :mcp_test_runs, :started_at
  end
end
