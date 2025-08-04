class CreateExperiences < ActiveRecord::Migration[8.0]
  def change
    create_table :experiences do |t|
      t.string :agent_label
      t.text :context
      t.text :narrative_text, null: false
      t.string :sentiment
      t.datetime :observed_at, null: false
      t.text :repr_text, null: false, limit: 500
      
      # Rights association
      t.references :provenance_and_rights, null: false, foreign_key: true
      
      # Optional actor reference (when Actor pool is present)
      t.bigint :actor_id

      t.timestamps
    end
    
    # Indexes
    add_index :experiences, :agent_label
    add_index :experiences, :sentiment
    add_index :experiences, :observed_at
    add_index :experiences, :actor_id
    
    # Full-text search
    add_index :experiences, :narrative_text, using: :gin, opclass: :gin_trgm_ops
  end
end