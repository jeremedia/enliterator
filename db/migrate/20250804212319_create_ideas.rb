class CreateIdeas < ActiveRecord::Migration[8.0]
  def change
    create_table :ideas do |t|
      t.string :label, null: false
      t.text :abstract, null: false
      t.jsonb :principle_tags, default: []
      t.string :authorship
      t.date :inception_date, null: false
      t.text :repr_text, null: false, limit: 500
      t.boolean :is_canonical, null: false, default: false
      
      # Rights association
      t.references :provenance_and_rights, null: false, foreign_key: true
      
      # Temporal tracking
      t.datetime :valid_time_start, null: false
      t.datetime :valid_time_end

      t.timestamps
    end
    
    # Indexes
    add_index :ideas, :label
    add_index :ideas, :principle_tags, using: :gin
    add_index :ideas, :is_canonical
    add_index :ideas, [:valid_time_start, :valid_time_end]
    
    # Full-text search index
    add_index :ideas, :label, using: :gin, opclass: :gin_trgm_ops
    add_index :ideas, :abstract, using: :gin, opclass: :gin_trgm_ops
  end
end