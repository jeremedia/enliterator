class CreateMcpTestSuites < ActiveRecord::Migration[8.0]
  def change
    create_table :mcp_test_suites do |t|
      t.string :name, null: false
      t.string :saved_prompt_id, null: false  # OpenAI pmpt_xxx ID
      t.json :base_variables  # {"SYSTEM_PROMPT": "...", "EKN_ID": "34", "TOOL_SEQUENCE": "search"}
      t.json :test_config     # {"timeout": 30, "max_retries": 3}
      t.text :description

      t.timestamps
    end
    
    add_index :mcp_test_suites, :name, unique: true
    add_index :mcp_test_suites, :saved_prompt_id
  end
end
