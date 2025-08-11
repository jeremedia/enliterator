# frozen_string_literal: true

# EKN Personality Profile - Tracks the developing personality of each Knowledge Navigator
#
# This model captures and evolves the unique personality characteristics of each EKN:
# - Knowledge source fingerprints (what data shaped this navigator?)
# - Ten Pool distribution preferences (Process-heavy vs Idea-focused?)
# - Response patterns and voice characteristics
# - Domain expertise and canonical vocabulary preferences
# - Relationship connection styles and interaction patterns
#
# Updated continuously through user interactions and meta-enliterator guidance.
#
class EknPersonalityProfile < ApplicationRecord
  belongs_to :ekn
  
  validates :ekn_id, uniqueness: true
  
  # Personality Archetype - Core personality type
  enum :base_archetype, {
    master_navigator: 'master_navigator',
    precision_analyst: 'precision_analyst', 
    systematic_explorer: 'systematic_explorer',
    relationship_mapper: 'relationship_mapper',
    domain_specialist: 'domain_specialist',
    creative_synthesizer: 'creative_synthesizer',
    data_detective: 'data_detective'
  }, validate: true

  # JSON fields for complex personality data
  attribute :knowledge_sources_fingerprint, :json, default: {}
  attribute :ten_pool_preferences, :json, default: {}
  attribute :response_patterns, :json, default: {}
  attribute :domain_expertise, :json, default: {}
  attribute :canonical_vocabulary, :json, default: {}
  attribute :relationship_styles, :json, default: {}
  attribute :voice_characteristics, :json, default: {}
  attribute :interaction_patterns, :json, default: {}
  attribute :evolution_history, :json, default: []
  
  # New archetype-specific fields
  attribute :mcp_tool_preferences, :json, default: {}
  attribute :query_transformation_style, :json, default: {}
  attribute :communication_signature, :json, default: {}
  attribute :expertise_depth_map, :json, default: {}
  attribute :visualization_driving_patterns, :json, default: {}
  attribute :learning_adaptation_style, :json, default: {}
  
  # Personality stability tracking
  attribute :personality_version, :integer, default: 1
  attribute :last_significant_change_at, :datetime
  
  scope :recent_changes, -> { where(last_significant_change_at: 1.week.ago..) }
  scope :stable_personalities, -> { where('last_significant_change_at < ?', 1.month.ago) }
  
  # Get the EKN's primary knowledge domains
  def primary_domains
    domain_expertise&.keys&.first(3) || []
  end
  
  # Get the EKN's preferred Ten Pool emphasis
  def dominant_pools
    return [] unless ten_pool_preferences.present?
    
    sorted_pools = ten_pool_preferences.sort_by { |_pool, weight| -weight }
    sorted_pools.first(2).map(&:first)
  end
  
  # Get the EKN's characteristic response style
  def response_style
    voice_characteristics&.dig('style') || 'balanced'
  end
  
  # Check if personality has changed significantly
  def personality_drift_detected?
    return false unless last_significant_change_at
    
    # Consider drift if multiple changes in short period
    recent_changes = evolution_history.select do |change|
      Time.parse(change['timestamp']) > 1.week.ago
    end
    
    recent_changes.size > 3
  end
  
  # === ARCHETYPE-SPECIFIC METHODS ===
  
  # Get archetype description
  def archetype_description
    case base_archetype&.to_sym
    when :master_navigator
      "Expert at meta-navigation and guiding users through complex knowledge landscapes"
    when :precision_analyst
      "Focused on detailed analysis with high accuracy and thorough verification"
    when :systematic_explorer
      "Methodical approach to discovering patterns and connections across domains"
    when :relationship_mapper
      "Specializes in understanding and visualizing entity relationships and dependencies"
    when :domain_specialist
      "Deep expertise in specific knowledge domains with authoritative responses"
    when :creative_synthesizer
      "Creative problem-solving by connecting disparate concepts in novel ways"
    when :data_detective
      "Investigative approach to uncovering hidden patterns and anomalies in data"
    else
      "Balanced general-purpose knowledge navigator"
    end
  end
  
  # Get preferred MCP tools based on archetype
  def preferred_mcp_tools
    base_preferences = mcp_tool_preferences.with_indifferent_access
    
    archetype_defaults = case base_archetype&.to_sym
    when :master_navigator
      { 'search' => 0.9, 'bridge' => 0.8, 'extract_and_link' => 0.7 }
    when :precision_analyst
      { 'fetch' => 0.9, 'search' => 0.8, 'extract_and_link' => 0.6 }
    when :systematic_explorer
      { 'search' => 0.8, 'bridge' => 0.9, 'location_neighbors' => 0.7 }
    when :relationship_mapper
      { 'bridge' => 0.9, 'location_neighbors' => 0.8, 'fetch' => 0.7 }
    when :domain_specialist
      { 'fetch' => 0.8, 'search' => 0.9, 'extract_and_link' => 0.7 }
    when :creative_synthesizer
      { 'bridge' => 0.8, 'extract_and_link' => 0.9, 'search' => 0.7 }
    when :data_detective
      { 'search' => 0.9, 'fetch' => 0.8, 'bridge' => 0.7 }
    else
      { 'search' => 0.8, 'fetch' => 0.6, 'bridge' => 0.5 }
    end
    
    # Merge archetype defaults with learned preferences
    archetype_defaults.merge(base_preferences) { |_key, default, learned| learned || default }
  end
  
  # Get communication style based on archetype
  def communication_style
    base_signature = communication_signature.with_indifferent_access
    
    archetype_defaults = case base_archetype&.to_sym
    when :master_navigator
      {
        'tone' => 'authoritative_yet_approachable',
        'detail_level' => 'contextual',
        'confidence_expression' => 'measured',
        'question_style' => 'guiding'
      }
    when :precision_analyst
      {
        'tone' => 'precise_analytical',
        'detail_level' => 'comprehensive',
        'confidence_expression' => 'evidence_based', 
        'question_style' => 'clarifying'
      }
    when :systematic_explorer
      {
        'tone' => 'methodical_curious',
        'detail_level' => 'structured',
        'confidence_expression' => 'process_oriented',
        'question_style' => 'exploratory'
      }
    when :relationship_mapper
      {
        'tone' => 'connection_focused',
        'detail_level' => 'relational',
        'confidence_expression' => 'pattern_based',
        'question_style' => 'linking'
      }
    when :domain_specialist
      {
        'tone' => 'expert_professional',
        'detail_level' => 'domain_deep',
        'confidence_expression' => 'authoritative',
        'question_style' => 'diagnostic'
      }
    when :creative_synthesizer
      {
        'tone' => 'creative_insightful',
        'detail_level' => 'conceptual',
        'confidence_expression' => 'inspirational',
        'question_style' => 'provocative'
      }
    when :data_detective
      {
        'tone' => 'investigative_curious',
        'detail_level' => 'evidence_focused',
        'confidence_expression' => 'discovery_based',
        'question_style' => 'probing'
      }
    else
      {
        'tone' => 'balanced_helpful',
        'detail_level' => 'appropriate',
        'confidence_expression' => 'honest',
        'question_style' => 'supportive'
      }
    end
    
    archetype_defaults.merge(base_signature) { |_key, default, learned| learned || default }
  end
  
  # Check if personality profile is ready for use
  def ready_for_chat?
    base_archetype.present? && 
    preferred_mcp_tools.any? && 
    communication_style.present?
  end
  
  # Get system prompt elements based on archetype
  def system_prompt_elements
    elements = {
      'archetype_role' => archetype_description,
      'communication_style' => communication_style,
      'tool_preferences' => preferred_mcp_tools,
      'domain_expertise' => primary_domains,
      'pool_emphasis' => dominant_pools
    }
    
    # Add visualization patterns if available
    if visualization_driving_patterns.any?
      elements['visualization_preferences'] = visualization_driving_patterns
    end
    
    elements
  end
  
  # Update personality based on new interaction data
  def update_personality!(interaction_data, meta_enliterator_guidance = nil)
    old_version = personality_version
    
    # Track the change
    change_record = {
      'timestamp' => Time.current.iso8601,
      'version' => personality_version + 1,
      'change_type' => 'interaction_based',
      'interaction_summary' => summarize_interaction(interaction_data),
      'meta_guidance' => meta_enliterator_guidance
    }
    
    # Update personality characteristics based on interaction
    update_ten_pool_preferences(interaction_data)
    update_response_patterns(interaction_data)
    update_voice_characteristics(interaction_data)
    
    # Record the evolution
    self.evolution_history = (evolution_history || []) + [change_record]
    self.personality_version += 1
    self.last_significant_change_at = Time.current if significant_change?(old_version)
    
    save!
  end
  
  # Generate a comprehensive personality summary for evaluation agents
  def personality_summary
    {
      'ekn_id' => ekn.id,
      'ekn_slug' => ekn.slug,
      'personality_version' => personality_version,
      'archetype_profile' => {
        'base_archetype' => base_archetype,
        'archetype_description' => archetype_description,
        'ready_for_chat' => ready_for_chat?,
        'mcp_tool_preferences' => preferred_mcp_tools,
        'communication_style' => communication_style,
        'system_prompt_elements' => system_prompt_elements
      },
      'knowledge_fingerprint' => {
        'primary_sources' => knowledge_sources_fingerprint&.dig('primary_sources') || [],
        'data_vintage' => knowledge_sources_fingerprint&.dig('vintage_summary'),
        'source_types' => knowledge_sources_fingerprint&.dig('source_types') || []
      },
      'ten_pool_distribution' => ten_pool_preferences,
      'dominant_pools' => dominant_pools,
      'response_characteristics' => {
        'typical_patterns' => response_patterns&.dig('common_structures') || [],
        'connection_preferences' => relationship_styles&.dig('preferred_relationships') || [],
        'voice_style' => response_style,
        'formality_level' => voice_characteristics&.dig('formality') || 'moderate'
      },
      'domain_expertise' => primary_domains,
      'canonical_vocabulary' => canonical_vocabulary&.dig('preferred_terms') || {},
      'advanced_capabilities' => {
        'expertise_depth_map' => expertise_depth_map,
        'visualization_driving_patterns' => visualization_driving_patterns,
        'learning_adaptation_style' => learning_adaptation_style
      },
      'personality_stability' => {
        'version' => personality_version,
        'last_change' => last_significant_change_at,
        'drift_detected' => personality_drift_detected?,
        'stability_score' => calculate_stability_score
      }
    }
  end
  
  # Get personality context for evaluation agents
  def evaluation_context
    """
    EKN ##{ekn.id} (#{ekn.slug}) - Personality Profile v#{personality_version}
    
    ARCHETYPE PROFILE:
    - Base Archetype: #{base_archetype&.humanize || 'Not Set'}
    - Description: #{archetype_description}
    - Ready for Chat: #{ready_for_chat? ? 'Yes' : 'No - Missing personality components'}
    - Preferred Tools: #{preferred_mcp_tools.map { |tool, weight| "#{tool}(#{weight})" }.join(', ')}
    
    COMMUNICATION SIGNATURE:
    - Tone: #{communication_style['tone'] || 'Not defined'}
    - Detail Level: #{communication_style['detail_level'] || 'Not defined'}
    - Confidence Expression: #{communication_style['confidence_expression'] || 'Not defined'}
    - Question Style: #{communication_style['question_style'] || 'Not defined'}
    
    KNOWLEDGE FINGERPRINT:
    - Primary Sources: #{knowledge_sources_fingerprint&.dig('primary_sources')&.join(', ') || 'Unknown'}
    - Data Vintage: #{knowledge_sources_fingerprint&.dig('vintage_summary') || 'Mixed'}
    - Source Types: #{knowledge_sources_fingerprint&.dig('source_types')&.join(', ') || 'Various'}
    
    TEN POOL PREFERENCES:
    - Dominant Pools: #{dominant_pools.join(' > ')}
    - Distribution: #{ten_pool_preferences&.map { |pool, weight| "#{pool}(#{weight})" }&.join(', ') || 'Balanced'}
    
    DOMAIN EXPERTISE:
    - Primary Domains: #{primary_domains.join(', ')}
    - Canonical Terms: #{canonical_vocabulary&.dig('preferred_terms')&.keys&.join(', ') || 'Standard'}
    - Expertise Depth: #{expertise_depth_map.keys.join(', ') || 'General'}
    
    ADVANCED CAPABILITIES:
    - Visualization Patterns: #{visualization_driving_patterns.keys.join(', ') || 'Not configured'}
    - Learning Style: #{learning_adaptation_style&.dig('primary_mode') || 'Standard'}
    
    PERSONALITY HEALTH:
    - Stability Score: #{calculate_stability_score}/100
    - Recent Changes: #{evolution_history&.last(3)&.size || 0}
    - Drift Detected: #{personality_drift_detected? ? 'Yes - Needs Attention' : 'No'}
    """
  end
  
  private
  
  def summarize_interaction(interaction_data)
    {
      'query_types' => interaction_data[:query_types] || [],
      'tools_used' => interaction_data[:tools_used] || [],
      'response_quality' => interaction_data[:response_quality] || 0.0,
      'user_satisfaction_signals' => interaction_data[:satisfaction_signals] || {}
    }
  end
  
  def update_ten_pool_preferences(interaction_data)
    # Update based on which pools were emphasized in successful interactions
    return unless interaction_data[:pool_usage]
    
    current_prefs = ten_pool_preferences || {}
    new_usage = interaction_data[:pool_usage]
    
    # Weighted average of current preferences and new evidence
    updated_prefs = {}
    all_pools = (current_prefs.keys + new_usage.keys).uniq
    
    all_pools.each do |pool|
      current_weight = current_prefs[pool] || 0.0
      new_evidence = new_usage[pool] || 0.0
      
      # 80% current, 20% new evidence (gradual evolution)
      updated_prefs[pool] = (current_weight * 0.8) + (new_evidence * 0.2)
    end
    
    self.ten_pool_preferences = updated_prefs
  end
  
  def update_response_patterns(interaction_data)
    # Track patterns that led to successful interactions
    return unless interaction_data[:successful_patterns]
    
    current_patterns = response_patterns || {}
    successful_patterns = interaction_data[:successful_patterns]
    
    # Reinforce successful patterns
    current_patterns['common_structures'] ||= {}
    successful_patterns.each do |pattern, frequency|
      current_patterns['common_structures'][pattern] = 
        ((current_patterns['common_structures'][pattern] || 0.0) * 0.9) + (frequency * 0.1)
    end
    
    self.response_patterns = current_patterns
  end
  
  def update_voice_characteristics(interaction_data)
    # Adjust voice based on user satisfaction with different styles
    return unless interaction_data[:voice_feedback]
    
    current_voice = voice_characteristics || {}
    feedback = interaction_data[:voice_feedback]
    
    # Gradual adjustment based on user preference signals
    if feedback[:preferred_formality]
      current_voice['formality'] = feedback[:preferred_formality]
    end
    
    if feedback[:preferred_detail_level]
      current_voice['detail_level'] = feedback[:preferred_detail_level]
    end
    
    self.voice_characteristics = current_voice
  end
  
  def significant_change?(old_version)
    # Define what constitutes a significant personality change
    version_jump = personality_version - old_version
    
    version_jump > 0 && (
      dominant_pools_changed? || 
      response_style_changed? || 
      major_preference_shift?
    )
  end
  
  def dominant_pools_changed?
    # Check if dominant pools shifted significantly
    return false unless evolution_history.size > 1
    
    previous = evolution_history[-2]
    return false unless previous
    
    # Compare current dominant pools to previous
    previous_summary = previous['interaction_summary']
    previous_pools = previous_summary&.dig('dominant_pools') || []
    
    (dominant_pools - previous_pools).any?
  end
  
  def response_style_changed?
    # Detect significant voice/style changes
    return false unless evolution_history.size > 1
    
    previous = evolution_history[-2]
    previous_style = previous&.dig('voice_style')
    
    previous_style && previous_style != response_style
  end
  
  def major_preference_shift?
    # Detect major shifts in Ten Pool preferences
    return false unless evolution_history.size > 1
    
    # Compare current vs previous Ten Pool distribution
    # Consider shift major if any pool changes by >0.3 weight
    false # Simplified for now
  end
  
  def calculate_stability_score
    # Calculate personality stability score (0-100)
    return 100 if evolution_history.blank?
    
    recent_changes = evolution_history.select do |change|
      Time.parse(change['timestamp']) > 2.weeks.ago
    end
    
    # More recent changes = lower stability
    base_score = 100
    penalty_per_change = 10
    
    stability = base_score - (recent_changes.size * penalty_per_change)
    [stability, 0].max
  end
end