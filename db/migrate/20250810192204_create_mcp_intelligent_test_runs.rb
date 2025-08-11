class CreateMcpIntelligentTestRuns < ActiveRecord::Migration[8.0]
  def change
    create_table :mcp_intelligent_test_runs do |t|
      t.references :mcp_test_run, null: false, foreign_key: true
      t.references :mcp_test_case, null: false, foreign_key: true
      t.references :ekn, null: false, foreign_key: true
      t.string :evaluator_type, null: false # claude_code_api, openai_proxy, fallback
      t.string :status, null: false        # pending, running, completed, failed
      t.json :agent_context                # Structured evaluation context
      t.json :evaluation_results           # Structured evaluation response
      t.json :performance_metrics          # Timing and performance data
      t.datetime :started_at
      t.datetime :completed_at
      t.integer :duration_ms
      t.text :error_message                # Error details if failed
      t.float :overall_score               # Denormalized overall score for queries

      t.timestamps
    end
    
    add_index :mcp_intelligent_test_runs, :evaluator_type
    add_index :mcp_intelligent_test_runs, :status
    add_index :mcp_intelligent_test_runs, :overall_score
    add_index :mcp_intelligent_test_runs, [:mcp_test_run_id, :status]
    add_index :mcp_intelligent_test_runs, [:ekn_id, :completed_at]
  end
end
