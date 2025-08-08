class AddResponseTypeToApiCalls < ActiveRecord::Migration[8.0]
  def change
    add_column :api_calls, :response_type, :string
  end
end
