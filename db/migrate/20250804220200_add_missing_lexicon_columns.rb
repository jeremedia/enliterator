# frozen_string_literal: true

class AddMissingLexiconColumns < ActiveRecord::Migration[8.0]
  def change
    add_column :lexicon_and_ontologies, :pool_association, :string, null: false, default: "unknown"
    add_column :lexicon_and_ontologies, :is_canonical, :boolean, null: false, default: false
    add_column :lexicon_and_ontologies, :relations, :jsonb, default: {}
    
    # Remove default after migration
    change_column_default :lexicon_and_ontologies, :pool_association, nil
  end
end