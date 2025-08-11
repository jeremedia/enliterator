class CreateEknPersonalityProfiles < ActiveRecord::Migration[8.0]
  def change
    create_table :ekn_personality_profiles do |t|
      t.references :ekn, null: false, foreign_key: true, index: { unique: true }
      t.json :knowledge_sources_fingerprint  # What data shaped this EKN
      t.json :ten_pool_preferences          # Pool emphasis patterns
      t.json :response_patterns             # Common response structures
      t.json :domain_expertise             # Areas of knowledge strength
      t.json :canonical_vocabulary         # Preferred terminology
      t.json :relationship_styles          # Connection preferences
      t.json :voice_characteristics        # Tone, formality, style
      t.json :interaction_patterns         # User interaction history
      t.json :evolution_history            # Personality change log
      t.integer :personality_version, default: 1, null: false
      t.datetime :last_significant_change_at

      t.timestamps
    end
    
    add_index :ekn_personality_profiles, :personality_version
    add_index :ekn_personality_profiles, :last_significant_change_at
    # Note: ekn_id index is created automatically by references
  end
end
