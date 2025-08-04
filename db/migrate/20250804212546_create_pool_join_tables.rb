class CreatePoolJoinTables < ActiveRecord::Migration[8.0]
  def change
    # Idea → Manifest (embodies)
    create_table :idea_manifests do |t|
      t.references :idea, null: false, foreign_key: true
      t.references :manifest, null: false, foreign_key: true
      t.string :relation_type, default: "embodies"
      t.float :strength
      t.timestamps
    end
    
    # Idea → Practical (codifies)
    create_table :idea_practicals do |t|
      t.references :idea, null: false, foreign_key: true
      t.references :practical, null: false, foreign_key: true
      t.string :relation_type, default: "codifies"
      t.float :strength
      t.timestamps
    end
    
    # Idea → Emanation (influences)
    create_table :idea_emanations do |t|
      t.references :idea, null: false, foreign_key: true
      t.references :emanation, null: false, foreign_key: true
      t.string :relation_type, default: "influences"
      t.float :strength
      t.timestamps
    end
    
    # Manifest → Experience (elicits)
    create_table :manifest_experiences do |t|
      t.references :manifest, null: false, foreign_key: true
      t.references :experience, null: false, foreign_key: true
      t.string :relation_type, default: "elicits"
      t.float :strength
      t.timestamps
    end
    
    # Experience → Emanation (inspires)
    create_table :experience_emanations do |t|
      t.references :experience, null: false, foreign_key: true
      t.references :emanation, null: false, foreign_key: true
      t.string :relation_type, default: "inspires"
      t.float :strength
      t.timestamps
    end
    
    # Experience ↔ Practical (validates/validated_by)
    create_table :experience_practicals do |t|
      t.references :experience, null: false, foreign_key: true
      t.references :practical, null: false, foreign_key: true
      t.string :relation_type # "validates" or "validated_by"
      t.float :strength
      t.timestamps
    end
    
    # Practical ↔ Idea (derived_from/informs)
    create_table :practical_ideas do |t|
      t.references :practical, null: false, foreign_key: true
      t.references :idea, null: false, foreign_key: true
      t.string :relation_type # "derived_from" or "informs"
      t.float :strength
      t.timestamps
    end
    
    # Emanation ↔ Idea (feeds_back/is_fed_by)
    create_table :emanation_ideas do |t|
      t.references :emanation, null: false, foreign_key: true
      t.references :idea, null: false, foreign_key: true
      t.string :relation_type # "feeds_back" or "is_fed_by"
      t.float :strength
      t.timestamps
    end
    
    # Emanation ↔ Relational (diffuses_through)
    create_table :emanation_relationals do |t|
      t.references :emanation, null: false, foreign_key: true
      t.references :relational, null: false, foreign_key: true
      t.string :relation_type, default: "diffuses_through"
      t.float :strength
      t.timestamps
    end
    
    # Add unique composite indexes to prevent duplicates
    add_index :idea_manifests, [:idea_id, :manifest_id], unique: true
    add_index :idea_practicals, [:idea_id, :practical_id], unique: true
    add_index :idea_emanations, [:idea_id, :emanation_id], unique: true
    add_index :manifest_experiences, [:manifest_id, :experience_id], unique: true
    add_index :experience_emanations, [:experience_id, :emanation_id], unique: true
    add_index :experience_practicals, [:experience_id, :practical_id, :relation_type], 
              unique: true, name: "index_exp_prac_on_ids_and_type"
    add_index :practical_ideas, [:practical_id, :idea_id, :relation_type], 
              unique: true, name: "index_prac_idea_on_ids_and_type"
    add_index :emanation_ideas, [:emanation_id, :idea_id, :relation_type], 
              unique: true, name: "index_eman_idea_on_ids_and_type"
    add_index :emanation_relationals, [:emanation_id, :relational_id], unique: true
  end
end