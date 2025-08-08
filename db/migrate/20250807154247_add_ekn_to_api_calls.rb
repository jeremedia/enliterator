class AddEknToApiCalls < ActiveRecord::Migration[8.0]
  def change
    add_reference :api_calls, :ekn, null: true, foreign_key: true
    add_index :api_calls, [:ekn_id, :created_at]
    add_index :api_calls, [:ekn_id, :endpoint]
    
    # Session reference already exists, just add an index if needed
    unless index_exists?(:api_calls, [:session_id, :created_at])
      add_index :api_calls, [:session_id, :created_at]
    end
  end
end
