# frozen_string_literal: true

class AddMissingEmanationColumns < ActiveRecord::Migration[8.0]
  def change
    add_column :emanations, :strength, :float
    add_column :emanations, :evidence_refs, :jsonb, default: []
    add_column :emanations, :temporal_extent, :jsonb, default: {}
  end
end