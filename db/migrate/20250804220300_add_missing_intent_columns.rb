# frozen_string_literal: true

class AddMissingIntentColumns < ActiveRecord::Migration[8.0]
  def change
    # Add missing columns
    add_column :intent_and_tasks, :raw_intent, :text
    add_column :intent_and_tasks, :normalized_intent, :jsonb, default: {}
    add_column :intent_and_tasks, :status, :integer, default: 0, null: false
    add_column :intent_and_tasks, :resolved_at, :datetime
    add_column :intent_and_tasks, :metadata, :jsonb, default: {}
    add_column :intent_and_tasks, :user_session_id, :bigint
    
    # Add temporal tracking columns if missing
    unless column_exists?(:intent_and_tasks, :valid_time_start)
      add_column :intent_and_tasks, :valid_time_start, :datetime, null: false, default: -> { 'CURRENT_TIMESTAMP' }
      add_column :intent_and_tasks, :valid_time_end, :datetime
    end
    
    # Ensure repr_text is not null
    change_column_null :intent_and_tasks, :repr_text, false, ""
    
    # Copy user_goal to raw_intent for existing records
    reversible do |direction|
      direction.up do
        execute "UPDATE intent_and_tasks SET raw_intent = user_goal WHERE raw_intent IS NULL"
      end
    end
    
    # Add index for status
    add_index :intent_and_tasks, :status
    add_index :intent_and_tasks, :resolved_at
  end
end