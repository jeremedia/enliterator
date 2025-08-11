class EnhanceEknPersonalityProfilesWithArchetypes < ActiveRecord::Migration[8.0]
  def change
    add_column :ekn_personality_profiles, :base_archetype, :string
    add_column :ekn_personality_profiles, :mcp_tool_preferences, :json, default: {}
    add_column :ekn_personality_profiles, :query_transformation_style, :json, default: {}
    add_column :ekn_personality_profiles, :communication_signature, :json, default: {}
    add_column :ekn_personality_profiles, :expertise_depth_map, :json, default: {}
    add_column :ekn_personality_profiles, :visualization_driving_patterns, :json, default: {}
    add_column :ekn_personality_profiles, :learning_adaptation_style, :json, default: {}
    
    add_index :ekn_personality_profiles, :base_archetype
  end
end
