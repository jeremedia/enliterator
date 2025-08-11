# frozen_string_literal: true

# PersonalityProfileGenerator - Analyzes EKNs to generate distinct personality profiles
#
# This service examines each EKN's knowledge graph, data sources, and interaction patterns
# to assign appropriate archetypes and generate comprehensive personality configurations.
#
# Usage:
#   # Generate profiles for all EKNs
#   PersonalityProfileGenerator.generate_all_profiles
#
#   # Generate profile for specific EKN
#   PersonalityProfileGenerator.generate_profile(ekn)
#
class PersonalityProfileGenerator
  attr_reader :ekn, :graph_stats, :knowledge_analysis
  
  def initialize(ekn)
    @ekn = ekn
    @graph_stats = nil
    @knowledge_analysis = nil
  end
  
  def self.generate_all_profiles
    Rails.logger.info "Starting personality profile generation for all EKNs"
    
    generated_count = 0
    updated_count = 0
    failed_count = 0
    
    Ekn.find_each do |ekn|
      begin
        generator = new(ekn)
        result = generator.generate_or_update_profile
        
        if result[:created]
          generated_count += 1
          Rails.logger.info "Generated new personality profile for EKN #{ekn.id} (#{ekn.slug})"
        else
          updated_count += 1
          Rails.logger.info "Updated existing personality profile for EKN #{ekn.id} (#{ekn.slug})"
        end
        
      rescue => e
        failed_count += 1
        Rails.logger.error "Failed to generate profile for EKN #{ekn.id}: #{e.message}"
      end
    end
    
    Rails.logger.info "Profile generation complete: #{generated_count} created, #{updated_count} updated, #{failed_count} failed"
    
    {
      total_processed: generated_count + updated_count + failed_count,
      generated: generated_count,
      updated: updated_count,
      failed: failed_count
    }
  end
  
  def generate_or_update_profile
    Rails.logger.info "Generating personality profile for EKN #{ekn.id} (#{ekn.slug})"
    
    # Analyze the EKN's knowledge characteristics
    analyze_knowledge_characteristics
    
    # Determine the best archetype
    archetype = determine_archetype
    
    # Generate personality configuration
    personality_config = generate_personality_configuration(archetype)
    
    # Create or update the profile
    profile = ekn.ekn_personality_profile || ekn.build_ekn_personality_profile
    
    created = profile.new_record?
    
    profile.assign_attributes(
      base_archetype: archetype,
      mcp_tool_preferences: personality_config[:mcp_tool_preferences],
      query_transformation_style: personality_config[:query_transformation_style],
      communication_signature: personality_config[:communication_signature],
      expertise_depth_map: personality_config[:expertise_depth_map],
      visualization_driving_patterns: personality_config[:visualization_driving_patterns],
      learning_adaptation_style: personality_config[:learning_adaptation_style],
      
      # Initialize basic personality fields if empty
      knowledge_sources_fingerprint: profile.knowledge_sources_fingerprint.presence || knowledge_analysis[:sources_fingerprint],
      ten_pool_preferences: profile.ten_pool_preferences.presence || knowledge_analysis[:pool_distribution],
      domain_expertise: profile.domain_expertise.presence || knowledge_analysis[:domain_expertise],
      voice_characteristics: profile.voice_characteristics.presence || personality_config[:voice_base],
      
      personality_version: profile.personality_version + (created ? 0 : 1),
      last_significant_change_at: created ? nil : Time.current
    )
    
    profile.save!
    
    Rails.logger.info "#{created ? 'Created' : 'Updated'} personality profile for EKN #{ekn.id} with archetype: #{archetype}"
    
    { profile: profile, created: created, archetype: archetype }
  end
  
  private
  
  def analyze_knowledge_characteristics
    @graph_stats = get_graph_statistics
    @knowledge_analysis = {
      sources_fingerprint: analyze_data_sources,
      pool_distribution: analyze_pool_distribution,
      domain_expertise: analyze_domain_patterns,
      relationship_patterns: analyze_relationship_patterns,
      complexity_metrics: calculate_complexity_metrics
    }
    
    Rails.logger.info "Knowledge analysis complete for EKN #{ekn.id}: #{@graph_stats[:total_nodes]} nodes, #{@graph_stats[:total_relationships]} relationships"
  end
  
  def get_graph_statistics
    if ekn.neo4j_database_exists?
      begin
        query_service = Graph::QueryService.new(ekn.neo4j_database_name)
        stats = query_service.get_statistics
        
        # Get additional stats we need
        session = Graph::Connection.instance.driver.session(database: ekn.neo4j_database_name)
        
        # Get pool distribution
        pool_counts = session.run("
          MATCH (n) 
          WITH labels(n)[0] as label, count(n) as count 
          RETURN label, count 
          ORDER BY count DESC
        ").map { |r| [r[:label], r[:count]] }.to_h
        
        # Get relationship types
        rel_counts = session.run("
          MATCH ()-[r]->() 
          WITH type(r) as rel_type, count(r) as count 
          RETURN rel_type, count 
          ORDER BY count DESC
        ").map { |r| [r[:rel_type], r[:count]] }.to_h
        
        session.close
        
        stats.merge(
          pool_distribution: pool_counts,
          relationship_types: rel_counts
        )
      rescue => e
        Rails.logger.error "Error getting graph statistics for EKN #{ekn.id}: #{e.message}"
        { total_nodes: 0, total_relationships: 0, pool_distribution: {}, relationship_types: {} }
      end
    else
      { total_nodes: 0, total_relationships: 0, pool_distribution: {}, relationship_types: {} }
    end
  end
  
  def analyze_data_sources
    # Analyze the EKN's ingest batches to understand data sources
    batches = ekn.ingest_batches.includes(:ingest_items)
    
    sources = batches.flat_map do |batch|
      batch.ingest_items.map do |item|
        {
          type: item.media_type || 'unknown',
          size: item.file_size || 0,
          batch_name: batch.name
        }
      end
    end
    
    {
      primary_sources: batches.pluck(:name).first(3),
      vintage_summary: "#{batches.count} batches from #{batches.minimum(:created_at)&.strftime('%Y-%m') || 'unknown'}",
      source_types: sources.map { |s| s[:type] }.uniq,
      total_items: sources.size,
      avg_item_size: sources.any? ? (sources.sum { |s| s[:size] } / sources.size) : 0
    }
  end
  
  def analyze_pool_distribution
    pool_counts = @graph_stats[:pool_distribution] || {}
    total_nodes = pool_counts.values.sum
    
    return {} if total_nodes.zero?
    
    # Convert to proportions
    pool_proportions = pool_counts.transform_values { |count| count.to_f / total_nodes }
    
    # Normalize to weights (0-1 scale)
    max_proportion = pool_proportions.values.max
    return {} if max_proportion.zero?
    
    pool_proportions.transform_values { |prop| (prop / max_proportion).round(3) }
  end
  
  def analyze_domain_patterns
    # Analyze domain patterns based on batch names and content types
    batch_names = ekn.ingest_batches.pluck(:name).join(' ').downcase
    
    domains = {}
    
    # Detect common domain patterns
    if batch_names.include?('burn') || batch_names.include?('playa') || batch_names.include?('art')
      domains['burning_man'] = 0.9
    end
    
    if batch_names.include?('research') || batch_names.include?('study')
      domains['research'] = 0.8
    end
    
    if batch_names.include?('tech') || batch_names.include?('code') || batch_names.include?('software')
      domains['technology'] = 0.7
    end
    
    if batch_names.include?('personal') || batch_names.include?('journal')
      domains['personal'] = 0.6
    end
    
    # Default domain if no specific patterns detected
    domains['general'] = 0.5 if domains.empty?
    
    domains
  end
  
  def analyze_relationship_patterns
    rel_types = @graph_stats[:relationship_types] || {}
    total_rels = rel_types.values.sum
    
    return {} if total_rels.zero?
    
    # Analyze relationship diversity and patterns
    {
      diversity_score: rel_types.keys.size / 10.0, # Normalize to 0-1 scale
      most_common: rel_types.keys.first(3),
      connection_density: total_rels.to_f / [@graph_stats[:total_nodes], 1].max,
      relationship_types: rel_types.transform_values { |count| count.to_f / total_rels }
    }
  end
  
  def calculate_complexity_metrics
    nodes = @graph_stats[:total_nodes] || 0
    relationships = @graph_stats[:total_relationships] || 0
    
    {
      graph_size: nodes + relationships,
      connectivity: nodes > 0 ? (relationships.to_f / nodes) : 0,
      structural_complexity: Math.log([nodes, 1].max) * Math.log([relationships, 1].max)
    }
  end
  
  def determine_archetype
    # Analyze patterns to determine the best archetype
    scores = {
      master_navigator: calculate_master_navigator_score,
      precision_analyst: calculate_precision_analyst_score,
      systematic_explorer: calculate_systematic_explorer_score,
      relationship_mapper: calculate_relationship_mapper_score,
      domain_specialist: calculate_domain_specialist_score,
      creative_synthesizer: calculate_creative_synthesizer_score,
      data_detective: calculate_data_detective_score
    }
    
    # Get the highest scoring archetype
    best_archetype = scores.max_by { |_archetype, score| score }&.first
    
    Rails.logger.info "Archetype scores for EKN #{ekn.id}: #{scores.inspect}"
    Rails.logger.info "Selected archetype: #{best_archetype}"
    
    best_archetype || :master_navigator
  end
  
  def calculate_master_navigator_score
    score = 0
    
    # Meta-Enliterator gets this archetype
    score += 100 if ekn.is_meta?
    
    # High diversity in pools and relationships suggests navigation capability
    pool_diversity = (@graph_stats[:pool_distribution]&.keys&.size || 0)
    score += pool_diversity * 5
    
    # Multiple batches suggests accumulation and meta-view
    score += ekn.ingest_batches.count * 3
    
    # Higher complexity suggests need for navigation
    score += @knowledge_analysis[:complexity_metrics][:structural_complexity] * 2
    
    score
  end
  
  def calculate_precision_analyst_score
    score = 0
    
    # High node-to-relationship ratio suggests detailed analysis
    connectivity = @knowledge_analysis[:complexity_metrics][:connectivity]
    score += (1.0 / [connectivity + 0.1, 0.1].max) * 20 if connectivity < 2.0
    
    # Research-oriented domains
    score += @knowledge_analysis[:domain_expertise]['research'].to_f * 30
    
    # Fewer but deeper sources
    source_count = @knowledge_analysis[:sources_fingerprint][:primary_sources].size
    score += (4.0 / [source_count, 1].max) * 10
    
    score
  end
  
  def calculate_systematic_explorer_score
    score = 0
    
    # Multiple pools with balanced distribution
    pool_distribution = @knowledge_analysis[:pool_distribution]
    if pool_distribution.any?
      balance_score = 1.0 - (pool_distribution.values.max - pool_distribution.values.min)
      score += balance_score * 40
    end
    
    # Multiple relationship types suggest systematic exploration
    rel_diversity = @knowledge_analysis[:relationship_patterns][:diversity_score] || 0
    score += rel_diversity * 30
    
    score
  end
  
  def calculate_relationship_mapper_score
    score = 0
    
    # High connectivity suggests relationship focus
    connectivity = @knowledge_analysis[:complexity_metrics][:connectivity]
    score += connectivity * 25 if connectivity > 1.5
    
    # High relationship diversity
    rel_diversity = @knowledge_analysis[:relationship_patterns][:diversity_score] || 0
    score += rel_diversity * 40
    
    # Dense connection patterns
    density = @knowledge_analysis[:relationship_patterns][:connection_density] || 0
    score += density * 100 if density > 0.3
    
    score
  end
  
  def calculate_domain_specialist_score
    score = 0
    
    # Strong domain expertise signals
    domain_strengths = @knowledge_analysis[:domain_expertise].values
    if domain_strengths.any?
      max_domain_strength = domain_strengths.max
      score += max_domain_strength * 60
    end
    
    # Focused source types (not diverse)
    source_types = @knowledge_analysis[:sources_fingerprint][:source_types].size
    score += (3.0 / [source_types, 1].max) * 15
    
    # Strong pool preferences
    pool_prefs = @knowledge_analysis[:pool_distribution].values
    if pool_prefs.any?
      score += pool_prefs.max * 25
    end
    
    score
  end
  
  def calculate_creative_synthesizer_score
    score = 0
    
    # High structural complexity suggests creative connections
    complexity = @knowledge_analysis[:complexity_metrics][:structural_complexity]
    score += complexity * 3
    
    # Diverse pools and relationships
    pool_count = @graph_stats[:pool_distribution]&.keys&.size || 0
    rel_count = @graph_stats[:relationship_types]&.keys&.size || 0
    
    score += (pool_count + rel_count) * 3
    
    # Multiple diverse source types
    source_diversity = @knowledge_analysis[:sources_fingerprint][:source_types].size
    score += source_diversity * 8
    
    score
  end
  
  def calculate_data_detective_score
    score = 0
    
    # High node count suggests investigative capacity
    nodes = @graph_stats[:total_nodes] || 0
    score += Math.log([nodes, 1].max) * 10
    
    # Multiple batches suggest investigation over time
    batch_count = ekn.ingest_batches.count
    score += batch_count * 5
    
    # Various source types suggest detective work
    source_count = @knowledge_analysis[:sources_fingerprint][:source_types].size
    score += source_count * 12
    
    score
  end
  
  def generate_personality_configuration(archetype)
    base_config = {
      mcp_tool_preferences: generate_mcp_preferences(archetype),
      query_transformation_style: generate_query_style(archetype),
      communication_signature: generate_communication_signature(archetype),
      expertise_depth_map: @knowledge_analysis[:domain_expertise],
      visualization_driving_patterns: generate_visualization_patterns(archetype),
      learning_adaptation_style: generate_learning_style(archetype),
      voice_base: generate_voice_characteristics(archetype)
    }
    
    Rails.logger.info "Generated personality configuration for archetype: #{archetype}"
    base_config
  end
  
  def generate_mcp_preferences(archetype)
    # Start with archetype defaults, adjust based on EKN characteristics
    base_prefs = case archetype
    when :master_navigator
      { 'search' => 0.9, 'bridge' => 0.8, 'extract_and_link' => 0.7, 'fetch' => 0.6 }
    when :precision_analyst
      { 'fetch' => 0.9, 'search' => 0.8, 'extract_and_link' => 0.6, 'bridge' => 0.4 }
    when :systematic_explorer
      { 'search' => 0.8, 'bridge' => 0.9, 'location_neighbors' => 0.7, 'fetch' => 0.6 }
    when :relationship_mapper
      { 'bridge' => 0.9, 'location_neighbors' => 0.8, 'fetch' => 0.7, 'search' => 0.5 }
    when :domain_specialist
      { 'fetch' => 0.8, 'search' => 0.9, 'extract_and_link' => 0.7, 'bridge' => 0.4 }
    when :creative_synthesizer
      { 'bridge' => 0.8, 'extract_and_link' => 0.9, 'search' => 0.7, 'fetch' => 0.5 }
    when :data_detective
      { 'search' => 0.9, 'fetch' => 0.8, 'bridge' => 0.7, 'extract_and_link' => 0.6 }
    else
      { 'search' => 0.8, 'fetch' => 0.6, 'bridge' => 0.5, 'extract_and_link' => 0.4 }
    end
    
    # Adjust based on graph characteristics
    connectivity = @knowledge_analysis[:complexity_metrics][:connectivity]
    if connectivity > 2.0
      base_prefs['bridge'] = [base_prefs['bridge'] + 0.1, 1.0].min
    end
    
    if @graph_stats[:total_nodes].to_i > 100
      base_prefs['search'] = [base_prefs['search'] + 0.1, 1.0].min
    end
    
    base_prefs
  end
  
  def generate_query_style(archetype)
    {
      'primary_approach' => case archetype
      when :master_navigator then 'meta_contextual'
      when :precision_analyst then 'detailed_verification'
      when :systematic_explorer then 'structured_discovery'
      when :relationship_mapper then 'connection_focused'
      when :domain_specialist then 'expertise_driven'
      when :creative_synthesizer then 'associative_exploration'
      when :data_detective then 'investigative_drilling'
      else 'balanced_exploration'
      end,
      'context_expansion' => archetype == :master_navigator ? 'high' : 'moderate',
      'precision_preference' => archetype == :precision_analyst ? 'high' : 'moderate'
    }
  end
  
  def generate_communication_signature(archetype)
    case archetype
    when :master_navigator
      {
        'tone' => 'authoritative_yet_approachable',
        'detail_level' => 'contextual_adaptive',
        'confidence_expression' => 'measured_expertise',
        'question_style' => 'guiding_discovery'
      }
    when :precision_analyst
      {
        'tone' => 'precise_analytical',
        'detail_level' => 'comprehensive_thorough',
        'confidence_expression' => 'evidence_based',
        'question_style' => 'clarifying_specific'
      }
    when :systematic_explorer
      {
        'tone' => 'methodical_curious',
        'detail_level' => 'structured_progressive',
        'confidence_expression' => 'process_confident',
        'question_style' => 'exploratory_building'
      }
    when :relationship_mapper
      {
        'tone' => 'connection_enthusiastic',
        'detail_level' => 'relational_contextual',
        'confidence_expression' => 'pattern_assured',
        'question_style' => 'linking_bridging'
      }
    when :domain_specialist
      {
        'tone' => 'expert_professional',
        'detail_level' => 'domain_deep',
        'confidence_expression' => 'authoritative_domain',
        'question_style' => 'diagnostic_focused'
      }
    when :creative_synthesizer
      {
        'tone' => 'creative_inspiring',
        'detail_level' => 'conceptual_connecting',
        'confidence_expression' => 'innovative_confident',
        'question_style' => 'provocative_synthesizing'
      }
    when :data_detective
      {
        'tone' => 'investigative_thorough',
        'detail_level' => 'evidence_focused',
        'confidence_expression' => 'discovery_driven',
        'question_style' => 'probing_analytical'
      }
    else
      {
        'tone' => 'balanced_helpful',
        'detail_level' => 'appropriate_adaptive',
        'confidence_expression' => 'honest_measured',
        'question_style' => 'supportive_open'
      }
    end
  end
  
  def generate_visualization_patterns(archetype)
    # Future capability - for now generate basic patterns
    {
      'preferred_formats' => case archetype
      when :master_navigator then ['network_maps', 'hierarchical_trees', 'flow_diagrams']
      when :precision_analyst then ['detailed_tables', 'comparison_charts', 'verification_matrices']
      when :systematic_explorer then ['step_diagrams', 'progressive_reveals', 'structured_layouts']
      when :relationship_mapper then ['network_graphs', 'connection_matrices', 'relationship_trees']
      when :domain_specialist then ['expertise_maps', 'domain_hierarchies', 'knowledge_trees']
      when :creative_synthesizer then ['concept_maps', 'creative_collages', 'synthesis_diagrams']
      when :data_detective then ['investigation_flows', 'evidence_chains', 'discovery_timelines']
      else ['balanced_layouts', 'adaptive_formats']
      end,
      'complexity_preference' => archetype == :precision_analyst ? 'detailed' : 'balanced'
    }
  end
  
  def generate_learning_style(archetype)
    {
      'primary_mode' => case archetype
      when :master_navigator then 'meta_learning'
      when :precision_analyst then 'verification_learning'
      when :systematic_explorer then 'structured_learning'
      when :relationship_mapper then 'connection_learning'
      when :domain_specialist then 'expertise_deepening'
      when :creative_synthesizer then 'synthesis_learning'
      when :data_detective then 'discovery_learning'
      else 'adaptive_learning'
      end,
      'adaptation_speed' => archetype == :creative_synthesizer ? 'rapid' : 'measured',
      'pattern_recognition' => archetype == :relationship_mapper ? 'high' : 'moderate'
    }
  end
  
  def generate_voice_characteristics(archetype)
    {
      'style' => case archetype
      when :master_navigator then 'authoritative_guide'
      when :precision_analyst then 'precise_analyst'
      when :systematic_explorer then 'methodical_explorer'
      when :relationship_mapper then 'connection_finder'
      when :domain_specialist then 'domain_expert'
      when :creative_synthesizer then 'creative_synthesizer'
      when :data_detective then 'investigative_detective'
      else 'balanced_helper'
      end,
      'formality' => archetype == :domain_specialist ? 'professional' : 'moderate'
    }
  end
end