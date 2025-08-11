class CreateMcpTestCases < ActiveRecord::Migration[8.0]
  def change
    create_table :mcp_test_cases do |t|
      t.references :mcp_test_suite, null: false, foreign_key: true
      t.string :name, null: false
      t.json :variable_overrides  # {"EKN_ID": "39", "QUERY": "renewable energy"}
      t.json :expectations        # {"tools_called": ["search", "fetch"], "min_results": 5}
      t.text :description
      t.boolean :enabled, default: true, null: false

      t.timestamps
    end
    
    add_index :mcp_test_cases, [:mcp_test_suite_id, :name], unique: true
    add_index :mcp_test_cases, :enabled
  end
end
