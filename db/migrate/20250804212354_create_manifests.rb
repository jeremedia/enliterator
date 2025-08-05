class CreateManifests < ActiveRecord::Migration[8.0]
  def change
    create_table :manifests do |t|
      t.string :label, null: false
      t.string :manifest_type
      t.jsonb :components, default: []
      t.jsonb :time_bounds, default: {}
      t.string :spatial_ref
      t.text :repr_text, null: false, limit: 500
      
      # Rights association
      t.references :provenance_and_rights, null: false, foreign_key: true
      
      # Temporal tracking
      t.datetime :valid_time_start, null: false
      t.datetime :valid_time_end

      t.timestamps
    end
    
    # Indexes
    add_index :manifests, :label
    add_index :manifests, :manifest_type
    add_index :manifests, :spatial_ref
    add_index :manifests, [:valid_time_start, :valid_time_end]
    add_index :manifests, :components, using: :gin
    
    # Full-text search
    add_index :manifests, :label, using: :gin, opclass: :gin_trgm_ops, name: 'index_manifests_on_label_trgm'
  end
end