# frozen_string_literal: true

# PersonalityToolRouter - Routes queries to MCP tools based on EKN personality profiles
#
# This service analyzes queries through the lens of an EKN's personality archetype
# and routes them to the most appropriate MCP tools with personality-enhanced parameters.
#
# Usage:
#   router = PersonalityToolRouter.new(ekn, query)
#   routing_result = router.route_with_personality
#   enhanced_params = router.enhance_tool_parameters(tool_name, base_params)
#
class PersonalityToolRouter
  attr_reader :ekn, :query, :profile
  
  def initialize(ekn, query)
    @ekn = ekn
    @query = query.to_s.strip
    @profile = ekn.ekn_personality_profile
    
    unless @profile&.ready_for_chat?
      Rails.logger.warn "EKN #{ekn.id} does not have a complete personality profile for routing"
    end
  end
  
  def route_with_personality
    return route_without_personality unless @profile&.ready_for_chat?
    
    Rails.logger.info "Routing query with personality: EKN #{ekn.id} (#{@profile.base_archetype})"
    
    # Analyze query characteristics
    query_analysis = analyze_query
    
    # Get archetype-specific routing preferences  
    archetype_preferences = get_archetype_preferences
    
    # Select optimal tool based on personality and query
    selected_tool = select_tool(query_analysis, archetype_preferences)
    
    # Enhance parameters based on personality
    base_params = build_base_parameters(selected_tool, query_analysis)
    enhanced_params = enhance_tool_parameters(selected_tool, base_params)
    
    # Build routing result
    {
      success: true,
      primary_tool: selected_tool,
      tool_params: enhanced_params,
      confidence: calculate_confidence(selected_tool, query_analysis),
      reasoning: build_routing_reasoning(selected_tool, query_analysis, archetype_preferences),
      archetype_influence: describe_archetype_influence(selected_tool),
      query_transformation: apply_query_transformation,
      canonical_entities: extract_canonical_entities,
      detected_pools: detect_relevant_pools(query_analysis)
    }
  end
  
  def enhance_tool_parameters(tool_name, base_params)
    return base_params unless @profile&.ready_for_chat?
    
    enhanced = base_params.dup
    
    case tool_name
    when 'search'
      enhanced = enhance_search_parameters(enhanced)
    when 'fetch'
      enhanced = enhance_fetch_parameters(enhanced)
    when 'bridge'
      enhanced = enhance_bridge_parameters(enhanced)
    when 'extract_and_link'
      enhanced = enhance_extract_link_parameters(enhanced)
    when 'location_neighbors'
      enhanced = enhance_location_parameters(enhanced)
    end
    
    # Apply archetype-specific parameter adjustments
    enhanced = apply_archetype_parameter_adjustments(tool_name, enhanced)
    
    Rails.logger.info "Enhanced #{tool_name} parameters for #{@profile.base_archetype}: #{enhanced.inspect}"
    
    enhanced
  end
  
  private
  
  def analyze_query
    analysis = {
      length: @query.length,
      word_count: @query.split.length,
      question_type: detect_question_type,
      complexity_indicators: detect_complexity_indicators,
      domain_hints: detect_domain_hints,
      relationship_cues: detect_relationship_cues,
      spatial_temporal_cues: detect_spatial_temporal_cues,
      meta_indicators: detect_meta_indicators
    }
    
    Rails.logger.debug "Query analysis: #{analysis.inspect}"
    analysis
  end
  
  def detect_question_type
    query_lower = @query.downcase
    
    return :what_is if query_lower.match?(/^what\s+(is|are|was|were)/)
    return :how_to if query_lower.match?(/^how\s+(do|can|to)/)
    return :why if query_lower.match?(/^why/)
    return :who if query_lower.match?(/^who/)
    return :where if query_lower.match?(/^where/)
    return :when if query_lower.match?(/^when/)
    return :which if query_lower.match?(/^which/)
    return :show_me if query_lower.match?(/^(show|display|list|find)/)
    return :explain if query_lower.match?(/(explain|describe|tell me about)/)
    return :compare if query_lower.match?(/(compare|versus|vs\.|difference between)/)
    return :connect if query_lower.match?(/(connect|relate|link|relationship between)/)
    
    :general
  end
  
  def detect_complexity_indicators
    indicators = []
    
    indicators << :multi_part if @query.match?(/\band\b|\bor\b|\bbut\b|\bhowever\b/)
    indicators << :conditional if @query.match?(/\bif\b|\bunless\b|\bwhen\b|\bwhile\b/)
    indicators << :comparative if @query.match?(/(better|worse|more|less|compared to|versus)/)
    indicators << :temporal if @query.match?(/(before|after|during|since|until|timeline)/)
    indicators << :causal if @query.match?(/(because|due to|caused by|leads to|results in)/)
    indicators << :quantitative if @query.match?(/(\d+|how many|how much|percentage|rate)/)
    
    indicators
  end
  
  def detect_domain_hints
    query_lower = @query.downcase
    domains = []
    
    # Check against EKN's known domain expertise
    @profile&.domain_expertise&.each do |domain, confidence|
      domain_keywords = get_domain_keywords(domain)
      if domain_keywords.any? { |keyword| query_lower.include?(keyword) }
        domains << { domain: domain, confidence: confidence }
      end
    end
    
    domains
  end
  
  def get_domain_keywords(domain)
    case domain.to_s.downcase
    when 'burning_man'
      ['burn', 'playa', 'art', 'camp', 'placement', 'temple', 'effigy', 'ranger']
    when 'technology'
      ['tech', 'software', 'code', 'programming', 'system', 'data', 'api']
    when 'research'
      ['study', 'analysis', 'research', 'findings', 'methodology', 'results']
    else
      []
    end
  end
  
  def detect_relationship_cues
    cues = []
    
    cues << :explicit_relationship if @query.match?(/(relationship|connection|link|relate|connect)/)
    cues << :bridge_seeking if @query.match?(/(between|and.*and|connects|bridges)/)
    cues << :network_thinking if @query.match?(/(network|web|system|interconnect)/)
    cues << :causality if @query.match?(/(cause|effect|influence|impact|affect)/)
    cues << :hierarchy if @query.match?(/(parent|child|under|above|contains|part of)/)
    
    cues
  end
  
  def detect_spatial_temporal_cues
    cues = []
    
    cues << :spatial if @query.match?(/(where|location|place|near|next to|around)/)
    cues << :temporal if @query.match?(/(when|time|date|year|before|after|during)/)
    cues << :chronological if @query.match?(/(timeline|history|sequence|order|evolution)/)
    cues << :geographic if @query.match?(/(map|coordinates|address|region|area)/)
    
    cues
  end
  
  def detect_meta_indicators
    indicators = []
    
    indicators << :overview_seeking if @query.match?(/(overview|summary|big picture|general)/)
    indicators << :navigation_help if @query.match?(/(help|guide|how to find|where to start)/)
    indicators << :framework_question if @query.match?(/(framework|system|approach|methodology)/)
    indicators << :guidance_request if @query.match?(/(should|recommend|suggest|advice|best)/)
    
    indicators
  end
  
  def get_archetype_preferences
    return {} unless @profile&.ready_for_chat?
    
    base_preferences = @profile.preferred_mcp_tools
    routing_rules = @profile.system_prompt_elements['archetype_routing_rules'] || {}
    
    {
      tool_weights: base_preferences,
      routing_rules: routing_rules,
      query_style: @profile.query_transformation_style,
      communication_style: @profile.communication_style
    }
  end
  
  def select_tool(query_analysis, archetype_preferences)
    tool_scores = {}
    
    # Get base tool preferences from personality
    tool_weights = archetype_preferences[:tool_weights] || {}
    
    # Score each available tool
    %w[search fetch bridge extract_and_link location_neighbors].each do |tool|
      score = calculate_tool_score(tool, query_analysis, tool_weights)
      tool_scores[tool] = score
    end
    
    # Select the highest scoring tool
    best_tool = tool_scores.max_by { |_tool, score| score }&.first
    
    Rails.logger.debug "Tool scores: #{tool_scores.inspect}, selected: #{best_tool}"
    
    best_tool || 'search' # Fallback to search
  end
  
  def calculate_tool_score(tool, query_analysis, tool_weights)
    base_score = tool_weights[tool]&.to_f || 0.5
    
    # Adjust score based on query characteristics
    case tool
    when 'search'
      base_score += 0.3 if query_analysis[:question_type].in?([:what_is, :show_me, :general])
      base_score += 0.2 if query_analysis[:complexity_indicators].include?(:multi_part)
    when 'fetch'
      base_score += 0.4 if query_analysis[:question_type].in?([:explain, :what_is])
      base_score += 0.2 if query_analysis[:domain_hints].any?
    when 'bridge'
      base_score += 0.5 if query_analysis[:relationship_cues].include?(:bridge_seeking)
      base_score += 0.3 if query_analysis[:question_type] == :connect
      base_score += 0.2 if query_analysis[:complexity_indicators].include?(:comparative)
    when 'extract_and_link'
      base_score += 0.4 if query_analysis[:relationship_cues].include?(:explicit_relationship)
      base_score += 0.3 if query_analysis[:question_type] == :connect
    when 'location_neighbors'
      base_score += 0.5 if query_analysis[:spatial_temporal_cues].include?(:spatial)
      base_score += 0.3 if query_analysis[:spatial_temporal_cues].include?(:geographic)
    end
    
    # Apply archetype-specific bonuses
    base_score = apply_archetype_tool_bonuses(tool, base_score, query_analysis)
    
    [base_score, 1.0].min # Cap at 1.0
  end
  
  def apply_archetype_tool_bonuses(tool, base_score, query_analysis)
    case @profile&.base_archetype&.to_sym
    when :master_navigator
      base_score += 0.2 if tool == 'search' && query_analysis[:meta_indicators].any?
      base_score += 0.1 if tool == 'bridge' && query_analysis[:question_type] == :general
    when :precision_analyst
      base_score += 0.3 if tool == 'fetch' && query_analysis[:question_type].in?([:explain, :what_is])
      base_score += 0.2 if tool == 'search' && query_analysis[:complexity_indicators].include?(:quantitative)
    when :relationship_mapper
      base_score += 0.4 if tool == 'bridge'
      base_score += 0.3 if tool == 'location_neighbors' && query_analysis[:spatial_temporal_cues].any?
    when :systematic_explorer
      base_score += 0.2 if tool == 'search' && query_analysis[:complexity_indicators].include?(:multi_part)
      base_score += 0.2 if tool == 'bridge' && query_analysis[:question_type] == :how_to
    when :creative_synthesizer
      base_score += 0.3 if tool == 'extract_and_link'
      base_score += 0.2 if tool == 'bridge' && query_analysis[:complexity_indicators].include?(:comparative)
    when :data_detective
      base_score += 0.3 if tool == 'search' && query_analysis[:complexity_indicators].any?
      base_score += 0.2 if tool == 'fetch' && query_analysis[:question_type] == :why
    end
    
    base_score
  end
  
  def build_base_parameters(tool_name, query_analysis)
    case tool_name
    when 'search'
      {
        query: @query,
        top_k: determine_result_count(query_analysis),
        pools: suggest_pools(query_analysis),
        require_rights: 'public'
      }
    when 'fetch'
      {
        # fetch requires an ID, which would come from prior search results
        # For routing purposes, we'll indicate fetch intent
        query: @query,
        include_relations: should_include_relations?(query_analysis),
        relation_depth: determine_relation_depth(query_analysis)
      }
    when 'bridge'
      {
        query: @query,
        top_k: determine_bridge_count(query_analysis)
      }
    when 'extract_and_link'
      {
        text: @query,
        mode: determine_extraction_mode(query_analysis),
        link_threshold: determine_link_threshold(query_analysis)
      }
    when 'location_neighbors'
      {
        query: @query,
        radius: determine_location_radius(query_analysis)
      }
    else
      { query: @query }
    end
  end
  
  def enhance_search_parameters(params)
    case @profile.base_archetype.to_sym
    when :master_navigator
      params[:top_k] = [params[:top_k], 15].max # More comprehensive results
      params[:diversify_by_pool] = true
    when :precision_analyst
      params[:top_k] = [params[:top_k], 5].min # Focused, high-quality results
      params[:include_trace] = true
    when :systematic_explorer
      params[:diversify_by_pool] = true
      params[:top_k] = [params[:top_k], 12].max
    when :relationship_mapper
      params[:include_relations] = true
      params[:relation_depth] = 2
    when :creative_synthesizer
      params[:top_k] = [params[:top_k], 20].max # Wide exploration
      params[:diversify_by_pool] = true
    when :data_detective
      params[:include_trace] = true
      params[:top_k] = [params[:top_k], 10].max
    end
    
    params
  end
  
  def enhance_fetch_parameters(params)
    case @profile.base_archetype.to_sym
    when :precision_analyst, :domain_specialist
      params[:include_relations] = true
      params[:relation_depth] = 3
    when :relationship_mapper
      params[:include_relations] = true
      params[:relation_depth] = 2
    when :systematic_explorer
      params[:include_timeline] = true
    end
    
    params
  end
  
  def enhance_bridge_parameters(params)
    case @profile.base_archetype.to_sym
    when :relationship_mapper
      params[:top_k] = [params[:top_k], 15].max
    when :creative_synthesizer
      params[:creative_connections] = true
      params[:top_k] = [params[:top_k], 10].max
    when :systematic_explorer
      params[:structured_paths] = true
    end
    
    params
  end
  
  def enhance_extract_link_parameters(params)
    case @profile.base_archetype.to_sym
    when :precision_analyst
      params[:link_threshold] = [params[:link_threshold], 0.8].max
    when :creative_synthesizer
      params[:link_threshold] = [params[:link_threshold], 0.5].min
      params[:mode] = 'creative_link'
    when :domain_specialist
      params[:domain_focus] = @profile.primary_domains
    end
    
    params
  end
  
  def enhance_location_parameters(params)
    case @profile.base_archetype.to_sym
    when :relationship_mapper
      params[:include_connections] = true
    when :systematic_explorer
      params[:structured_layout] = true
    end
    
    params
  end
  
  def apply_archetype_parameter_adjustments(tool_name, params)
    # Apply communication style preferences
    case @profile.communication_style['detail_level']
    when 'comprehensive_thorough', 'domain_deep'
      if params[:top_k]
        params[:top_k] = [params[:top_k] * 1.2, 25].min.to_i
      end
    when 'contextual_adaptive'
      # Adjust based on query complexity
      if @query.split.length > 10
        params[:top_k] = [params[:top_k] * 1.1, 15].min.to_i if params[:top_k]
      end
    end
    
    params
  end
  
  def determine_result_count(query_analysis)
    base_count = 10
    
    base_count += 3 if query_analysis[:complexity_indicators].include?(:multi_part)
    base_count += 2 if query_analysis[:question_type] == :compare
    base_count -= 2 if query_analysis[:question_type].in?([:what_is, :explain])
    
    [base_count, 25].min
  end
  
  def should_include_relations?(query_analysis)
    query_analysis[:relationship_cues].any? || 
    query_analysis[:question_type].in?([:connect, :explain, :how_to])
  end
  
  def determine_relation_depth(query_analysis)
    return 3 if query_analysis[:complexity_indicators].include?(:multi_part)
    return 2 if query_analysis[:relationship_cues].include?(:network_thinking)
    1
  end
  
  def determine_bridge_count(query_analysis)
    return 15 if query_analysis[:complexity_indicators].include?(:comparative)
    return 12 if query_analysis[:relationship_cues].include?(:network_thinking)
    8
  end
  
  def determine_extraction_mode(query_analysis)
    return 'link' if query_analysis[:relationship_cues].any?
    return 'classify' if query_analysis[:question_type] == :what_is
    'extract'
  end
  
  def determine_link_threshold(query_analysis)
    return 0.8 if @profile&.base_archetype == 'precision_analyst'
    return 0.5 if @profile&.base_archetype == 'creative_synthesizer'
    0.6
  end
  
  def determine_location_radius(query_analysis)
    return 'neighborhood' if query_analysis[:spatial_temporal_cues].include?(:geographic)
    return 'adjacent' if query_analysis[:question_type] == :where
    'immediate'
  end
  
  def suggest_pools(query_analysis)
    # Suggest pools based on query analysis and archetype preferences
    suggested = []
    
    # Use domain hints
    query_analysis[:domain_hints].each do |hint|
      case hint[:domain]
      when 'burning_man'
        suggested.concat(['Manifest', 'Location', 'Experience'])
      when 'technology'
        suggested.concat(['Process', 'Idea'])
      end
    end
    
    # Use dominant pools from personality
    if suggested.empty? && @profile
      suggested = @profile.dominant_pools.map(&:capitalize)
    end
    
    suggested.uniq.first(3)
  end
  
  def calculate_confidence(selected_tool, query_analysis)
    base_confidence = 0.7
    
    # Increase confidence if tool aligns well with query
    tool_query_alignment = case selected_tool
    when 'search'
      query_analysis[:question_type].in?([:what_is, :show_me, :general]) ? 0.2 : 0.0
    when 'bridge'
      query_analysis[:relationship_cues].any? ? 0.3 : 0.0
    when 'fetch'
      query_analysis[:question_type].in?([:explain, :what_is]) ? 0.2 : 0.0
    else
      0.1
    end
    
    # Increase confidence if archetype strongly prefers this tool
    archetype_alignment = if @profile&.preferred_mcp_tools&.dig(selected_tool).to_f > 0.8
      0.2
    else
      0.0
    end
    
    [base_confidence + tool_query_alignment + archetype_alignment, 1.0].min
  end
  
  def build_routing_reasoning(selected_tool, query_analysis, archetype_preferences)
    reasons = []
    
    # Archetype reasoning
    archetype_desc = @profile&.archetype_description || "Balanced navigator"
    reasons << "Selected #{selected_tool} as #{archetype_desc.downcase}"
    
    # Query analysis reasoning
    if query_analysis[:question_type] != :general
      reasons << "Query type (#{query_analysis[:question_type].to_s.humanize.downcase}) aligns with #{selected_tool} capabilities"
    end
    
    # Personality preference reasoning
    tool_weight = archetype_preferences[:tool_weights]&.dig(selected_tool) || 0.5
    if tool_weight > 0.7
      reasons << "High personality preference for #{selected_tool} (#{(tool_weight * 100).round}%)"
    end
    
    # Complexity reasoning
    if query_analysis[:complexity_indicators].any?
      reasons << "Query complexity indicators: #{query_analysis[:complexity_indicators].join(', ')}"
    end
    
    reasons.join('. ')
  end
  
  def describe_archetype_influence(selected_tool)
    return "No personality profile available" unless @profile&.ready_for_chat?
    
    archetype = @profile.base_archetype
    tool_pref = @profile.preferred_mcp_tools[selected_tool] || 0.5
    
    "#{archetype.humanize} archetype influences tool selection (#{selected_tool} preference: #{(tool_pref * 100).round}%)"
  end
  
  def apply_query_transformation
    return @query unless @profile&.ready_for_chat?
    
    transformation_style = @profile.query_transformation_style['primary_approach']
    
    case transformation_style
    when 'meta_contextual'
      # Master Navigator: Add meta-context
      "#{@query} [Context: seeking comprehensive understanding with navigation guidance]"
    when 'detailed_verification'
      # Precision Analyst: Add verification focus
      "#{@query} [Focus: detailed accuracy and evidence verification required]"
    when 'structured_discovery'
      # Systematic Explorer: Add structured approach
      "#{@query} [Approach: systematic exploration with structured results]"
    when 'connection_focused'
      # Relationship Mapper: Add relationship emphasis
      "#{@query} [Emphasis: relationships and connections between entities]"
    when 'expertise_driven'
      # Domain Specialist: Add expertise context
      domains = @profile.primary_domains.join(', ')
      "#{@query} [Expertise context: #{domains}]"
    when 'associative_exploration'
      # Creative Synthesizer: Add creative context
      "#{@query} [Mode: creative synthesis and novel connections]"
    when 'investigative_drilling'
      # Data Detective: Add investigative context
      "#{@query} [Investigation: thorough analysis and pattern discovery]"
    else
      @query
    end
  end
  
  def extract_canonical_entities
    # Simple entity extraction - in production this would use the extract_and_link tool
    entities = []
    
    # Extract potential entities (capitalized words, quoted terms, etc.)
    entities.concat(@query.scan(/\b[A-Z][a-z]+\b/))
    entities.concat(@query.scan(/"([^"]+)"/))
    entities.concat(@query.scan(/'([^']+)'/))
    
    entities.flatten.uniq.first(5)
  end
  
  def detect_relevant_pools(query_analysis)
    pools = Set.new
    
    # Based on question type
    case query_analysis[:question_type]
    when :what_is, :explain
      pools << 'Idea'
    when :who
      pools << 'Individual' << 'Organization'
    when :where
      pools << 'Location'
    when :when
      pools << 'Temporal'
    when :how_to
      pools << 'Process'
    end
    
    # Based on domain hints
    query_analysis[:domain_hints].each do |hint|
      case hint[:domain]
      when 'burning_man'
        pools << 'Manifest' << 'Location' << 'Experience'
      when 'technology'
        pools << 'Process' << 'Idea'
      end
    end
    
    # Based on relationship cues
    if query_analysis[:relationship_cues].any?
      pools << 'Process' << 'Outcome'
    end
    
    pools.to_a
  end
  
  def route_without_personality
    {
      success: true,
      primary_tool: 'search',
      tool_params: { query: @query, top_k: 10, require_rights: 'public' },
      confidence: 0.5,
      reasoning: "No personality profile available - using basic search routing",
      archetype_influence: "No personality profile configured",
      query_transformation: @query,
      canonical_entities: extract_canonical_entities,
      detected_pools: ['Idea', 'Process', 'Manifest']
    }
  end
end