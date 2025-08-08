class CreateOptionalPools < ActiveRecord::Migration[8.0]
  def change
    # Actor Pool - Agents/actors who perform actions
    create_table :actors do |t|
      t.string :name, null: false
      t.string :role
      t.text :description
      t.jsonb :capabilities, default: []
      t.jsonb :affiliations, default: []
      t.text :repr_text, null: false
      t.references :provenance_and_rights, null: false, foreign_key: true
      t.datetime :valid_time_start, null: false
      t.datetime :valid_time_end
      
      t.timestamps
      
      t.index :name
      t.index :role
      t.index [:valid_time_start, :valid_time_end]
    end
    
    # Spatial Pool - Location and spatial information
    create_table :spatials do |t|
      t.string :location_name, null: false
      t.string :sector
      t.string :portal
      t.integer :year
      t.jsonb :coordinates, default: {}
      t.jsonb :neighbors, default: []
      t.string :placement_type
      t.text :description
      t.text :repr_text, null: false
      t.references :provenance_and_rights, null: false, foreign_key: true
      t.datetime :valid_time_start, null: false
      t.datetime :valid_time_end
      
      t.timestamps
      
      t.index :location_name
      t.index :sector
      t.index :portal
      t.index :year
      t.index [:valid_time_start, :valid_time_end]
    end
    
    # Evidence Pool - Supporting evidence or proof
    create_table :evidences do |t|
      t.string :evidence_type, null: false
      t.text :description, null: false
      t.jsonb :source_refs, default: []
      t.float :confidence_score
      t.jsonb :corroboration, default: []
      t.text :repr_text, null: false
      t.references :provenance_and_rights, null: false, foreign_key: true
      t.datetime :observed_at, null: false
      
      t.timestamps
      
      t.index :evidence_type
      t.index :confidence_score
      t.index :observed_at
    end
    
    # Risk Pool - Risks, hazards, or dangers
    create_table :risks do |t|
      t.string :risk_type, null: false
      t.string :severity
      t.float :probability
      t.text :description, null: false
      t.jsonb :mitigations, default: []
      t.jsonb :impacts, default: []
      t.text :repr_text, null: false
      t.references :provenance_and_rights, null: false, foreign_key: true
      t.datetime :valid_time_start, null: false
      t.datetime :valid_time_end
      
      t.timestamps
      
      t.index :risk_type
      t.index :severity
      t.index :probability
      t.index [:valid_time_start, :valid_time_end]
    end
    
    # MethodPool - Methods, procedures, or techniques
    # Using 'method_pools' to avoid conflict with Ruby's Method class
    create_table :method_pools do |t|
      t.string :method_name, null: false
      t.string :category
      t.text :description, null: false
      t.jsonb :steps, default: []
      t.jsonb :prerequisites, default: []
      t.jsonb :outcomes, default: []
      t.text :repr_text, null: false
      t.references :provenance_and_rights, null: false, foreign_key: true
      t.datetime :valid_time_start, null: false
      t.datetime :valid_time_end
      
      t.timestamps
      
      t.index :method_name
      t.index :category
      t.index [:valid_time_start, :valid_time_end]
    end
    
    # Join tables for relationships between optional pools and core pools
    
    # Actor relationships
    create_table :actor_experiences do |t|
      t.references :actor, null: false, foreign_key: true
      t.references :experience, null: false, foreign_key: true
      t.string :relation_type, default: 'participates_in'
      t.float :strength
      
      t.timestamps
      
      t.index [:actor_id, :experience_id], unique: true
    end
    
    create_table :actor_manifests do |t|
      t.references :actor, null: false, foreign_key: true
      t.references :manifest, null: false, foreign_key: true
      t.string :relation_type, default: 'interacts_with'
      t.float :strength
      
      t.timestamps
      
      t.index [:actor_id, :manifest_id], unique: true
    end
    
    # Spatial relationships
    create_table :manifest_spatials do |t|
      t.references :manifest, null: false, foreign_key: true
      t.references :spatial, null: false, foreign_key: true
      t.string :relation_type, default: 'located_at'
      t.float :strength
      
      t.timestamps
      
      t.index [:manifest_id, :spatial_id], unique: true
    end
    
    # Evidence relationships
    create_table :evidence_experiences do |t|
      t.references :evidence, null: false, foreign_key: true
      t.references :experience, null: false, foreign_key: true
      t.string :relation_type, default: 'supports'
      t.float :strength
      
      t.timestamps
      
      t.index [:evidence_id, :experience_id], unique: true
    end
    
    # Risk relationships
    create_table :risk_practicals do |t|
      t.references :risk, null: false, foreign_key: true
      t.references :practical, null: false, foreign_key: true
      t.string :relation_type, default: 'mitigated_by'
      t.float :strength
      
      t.timestamps
      
      t.index [:risk_id, :practical_id], unique: true
    end
    
    # Method relationships
    create_table :method_pool_practicals do |t|
      t.references :method_pool, null: false, foreign_key: true
      t.references :practical, null: false, foreign_key: true
      t.string :relation_type, default: 'implements'
      t.float :strength
      
      t.timestamps
      
      t.index [:method_pool_id, :practical_id], unique: true
    end
  end
end