# frozen_string_literal: true

class AddMissingReprTextColumns < ActiveRecord::Migration[8.0]
  def change
    # Add repr_text to tables that are missing it
    add_column :relationals, :repr_text, :text, null: false, default: "", limit: 500
    add_column :evolutionaries, :repr_text, :text, null: false, default: "", limit: 500
    add_column :lexicon_and_ontologies, :repr_text, :text, null: false, default: "", limit: 500
    
    # Also add change_summary to evolutionaries (referenced in model but missing)
    add_column :evolutionaries, :change_summary, :text, null: false, default: ""
    add_column :evolutionaries, :delta_metrics, :jsonb, default: {}
    
    # Remove default after migration
    change_column_default :relationals, :repr_text, nil
    change_column_default :evolutionaries, :repr_text, nil
    change_column_default :lexicon_and_ontologies, :repr_text, nil
    change_column_default :evolutionaries, :change_summary, nil
  end
end