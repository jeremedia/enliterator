class CreateRemainingCorePools < ActiveRecord::Migration[8.0]
  def change
    # Relational pool
    create_table :relationals do |t|
      t.string :relation_type, null: false
      t.references :source, polymorphic: true, null: false
      t.references :target, polymorphic: true, null: false
      t.float :strength
      t.jsonb :period, default: {}
      t.references :provenance_and_rights, null: false, foreign_key: true
      t.datetime :valid_time_start, null: false
      t.datetime :valid_time_end
      t.timestamps
    end
    
    # Evolutionary pool
    create_table :evolutionaries do |t|
      t.text :change_note, null: false
      t.references :prior_ref, polymorphic: true
      t.string :version_id
      t.references :refined_idea, foreign_key: { to_table: :ideas }
      t.references :manifest_version, foreign_key: { to_table: :manifests }
      t.references :provenance_and_rights, null: false, foreign_key: true
      t.datetime :valid_time_start, null: false
      t.datetime :valid_time_end
      t.timestamps
    end
    
    # Practical pool
    create_table :practicals do |t|
      t.string :goal, null: false
      t.jsonb :steps, default: []
      t.jsonb :prerequisites, default: []
      t.jsonb :hazards, default: []
      t.jsonb :validation_refs, default: []
      t.text :repr_text, null: false, limit: 500
      t.references :provenance_and_rights, null: false, foreign_key: true
      t.datetime :valid_time_start, null: false
      t.datetime :valid_time_end
      t.timestamps
    end
    
    # Emanation pool
    create_table :emanations do |t|
      t.string :influence_type, null: false
      t.text :target_context
      t.text :pathway
      t.text :evidence
      t.text :repr_text, null: false, limit: 500
      t.references :provenance_and_rights, null: false, foreign_key: true
      t.datetime :valid_time_start, null: false
      t.datetime :valid_time_end
      t.timestamps
    end
    
    # Lexicon and Ontology pool
    create_table :lexicon_and_ontologies do |t|
      t.string :term, null: false
      t.text :definition
      t.text :canonical_description
      t.jsonb :surface_forms, default: []
      t.jsonb :negative_surface_forms, default: []
      t.jsonb :type_mapping, default: {}
      t.string :unit_system
      t.string :schema_version
      t.references :provenance_and_rights, null: false, foreign_key: true
      t.datetime :valid_time_start, null: false
      t.datetime :valid_time_end
      t.timestamps
    end
    
    # Intent and Task pool
    create_table :intent_and_tasks do |t|
      t.text :user_goal, null: false
      t.text :query_text
      t.jsonb :presentation_preference, default: {}
      t.string :outcome_signal
      t.jsonb :success_criteria, default: {}
      t.text :repr_text, limit: 500
      
      # Extended fields for delivery
      t.string :deliverable_type
      t.string :modality
      t.jsonb :constraints, default: {}
      t.string :adapter_name
      t.jsonb :adapter_params, default: {}
      t.jsonb :evaluation, default: {}
      
      t.datetime :observed_at, null: false
      t.references :provenance_and_rights, null: false, foreign_key: true
      t.timestamps
    end
    
    # Indexes for Relational
    add_index :relationals, :relation_type
    add_index :relationals, [:source_type, :source_id]
    add_index :relationals, [:target_type, :target_id]
    add_index :relationals, [:valid_time_start, :valid_time_end]
    
    # Indexes for Evolutionary
    add_index :evolutionaries, :version_id
    add_index :evolutionaries, [:prior_ref_type, :prior_ref_id]
    add_index :evolutionaries, [:valid_time_start, :valid_time_end]
    
    # Indexes for Practical
    add_index :practicals, :goal
    add_index :practicals, :steps, using: :gin
    add_index :practicals, [:valid_time_start, :valid_time_end]
    
    # Indexes for Emanation
    add_index :emanations, :influence_type
    add_index :emanations, [:valid_time_start, :valid_time_end]
    
    # Indexes for Lexicon
    add_index :lexicon_and_ontologies, :term, unique: true
    add_index :lexicon_and_ontologies, :surface_forms, using: :gin
    add_index :lexicon_and_ontologies, :negative_surface_forms, using: :gin
    add_index :lexicon_and_ontologies, [:valid_time_start, :valid_time_end]
    
    # Indexes for Intent
    add_index :intent_and_tasks, :deliverable_type
    add_index :intent_and_tasks, :modality
    add_index :intent_and_tasks, :observed_at
  end
end