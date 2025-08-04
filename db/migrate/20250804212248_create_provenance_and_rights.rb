class CreateProvenanceAndRights < ActiveRecord::Migration[8.0]
  def change
    create_table :provenance_and_rights do |t|
      # Source tracking
      t.jsonb :source_ids, null: false, default: []
      t.string :source_owner
      t.jsonb :collectors, default: []
      t.string :collection_method, null: false
      
      # Rights and licensing
      t.integer :consent_status, null: false, default: 0
      t.integer :license_type, null: false, default: 0
      t.jsonb :custom_terms, default: {}
      
      # Derived fields
      t.boolean :publishability, null: false, default: false
      t.boolean :training_eligibility, null: false, default: false
      
      # Embargo and quarantine
      t.datetime :embargo_until
      t.boolean :quarantined, null: false, default: false
      t.string :quarantine_reason
      
      # Temporal tracking
      t.datetime :valid_time_start, null: false
      t.datetime :valid_time_end

      t.timestamps
    end
    
    # Indexes for performance
    add_index :provenance_and_rights, :publishability
    add_index :provenance_and_rights, :training_eligibility
    add_index :provenance_and_rights, :quarantined
    add_index :provenance_and_rights, :embargo_until
    add_index :provenance_and_rights, :source_ids, using: :gin
    add_index :provenance_and_rights, [:valid_time_start, :valid_time_end]
    
    # Composite indexes for common queries
    add_index :provenance_and_rights, [:publishability, :training_eligibility], 
              name: 'index_p_and_r_on_publish_and_train'
  end
end