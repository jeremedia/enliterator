# frozen_string_literal: true

# PersonalityResponseSynthesizer - Converts raw tool results into archetype-specific responses
#
# This service takes MCP tool results and transforms them into responses that reflect
# the specific personality archetype, communication style, and voice patterns of each EKN.
#
# Usage:
#   synthesizer = PersonalityResponseSynthesizer.new(ekn)
#   response = synthesizer.synthesize_response(tool_results, query_context)
#
class PersonalityResponseSynthesizer
  attr_reader :ekn, :profile
  
  def initialize(ekn)
    @ekn = ekn
    @profile = ekn.ekn_personality_profile
    
    unless @profile&.ready_for_chat?
      Rails.logger.warn "EKN #{ekn.id} does not have a complete personality profile for response synthesis"
    end
  end
  
  def synthesize_response(tool_results, query_context = {})
    return synthesize_fallback_response(tool_results) unless @profile&.ready_for_chat?
    
    Rails.logger.info "Synthesizing response for EKN #{ekn.id} (#{@profile.base_archetype})"
    
    # Extract key information from tool results
    response_data = extract_response_data(tool_results)
    
    # Build archetype-specific response structure
    response_structure = build_response_structure(response_data, query_context)
    
    # Apply communication style patterns
    styled_response = apply_communication_style(response_structure)
    
    # Add archetype-specific flourishes and voice patterns
    final_response = apply_voice_patterns(styled_response, response_data)
    
    # Include citations and metadata in archetype-appropriate format
    complete_response = add_citations_and_metadata(final_response, response_data)
    
    Rails.logger.info "Response synthesized for #{@profile.base_archetype}: #{complete_response.length} characters"
    
    complete_response
  end
  
  def get_response_template(response_type)
    return get_fallback_template(response_type) unless @profile&.ready_for_chat?
    
    case @profile.base_archetype.to_sym
    when :master_navigator
      get_master_navigator_template(response_type)
    when :precision_analyst
      get_precision_analyst_template(response_type)
    when :systematic_explorer
      get_systematic_explorer_template(response_type)
    when :relationship_mapper
      get_relationship_mapper_template(response_type)
    when :domain_specialist
      get_domain_specialist_template(response_type)
    when :creative_synthesizer
      get_creative_synthesizer_template(response_type)
    when :data_detective
      get_data_detective_template(response_type)
    else
      get_fallback_template(response_type)
    end
  end
  
  private
  
  def extract_response_data(tool_results)
    {
      primary_results: tool_results[:items] || [],
      total_results: tool_results.dig(:meta, :total_found) || 0,
      citations: tool_results[:citations] || [],
      path_sentences: tool_results[:path_sentences] || [],
      enrichments: tool_results[:enrichments] || [],
      tool_used: tool_results[:tool_used] || 'unknown',
      confidence: tool_results[:confidence] || 0.0,
      reasoning: tool_results[:reasoning] || '',
      query_transformation: tool_results[:query_transformation] || '',
      detected_pools: tool_results[:detected_pools] || []
    }
  end
  
  def build_response_structure(response_data, query_context)
    structure = {
      opening: build_opening_section(response_data, query_context),
      main_content: build_main_content_section(response_data),
      connections: build_connections_section(response_data),
      conclusion: build_conclusion_section(response_data, query_context)
    }
    
    # Filter out empty sections
    structure.compact
  end
  
  def build_opening_section(response_data, query_context)
    return nil if response_data[:primary_results].empty?
    
    case @profile.base_archetype.to_sym
    when :master_navigator
      build_navigator_opening(response_data, query_context)
    when :precision_analyst
      build_analyst_opening(response_data, query_context)
    when :systematic_explorer
      build_explorer_opening(response_data, query_context)
    when :relationship_mapper
      build_mapper_opening(response_data, query_context)
    when :domain_specialist
      build_specialist_opening(response_data, query_context)
    when :creative_synthesizer
      build_synthesizer_opening(response_data, query_context)
    when :data_detective
      build_detective_opening(response_data, query_context)
    else
      build_general_opening(response_data, query_context)
    end
  end
  
  def build_navigator_opening(response_data, query_context)
    if response_data[:total_results] > 10
      "I'll guide you through the knowledge landscape I've discovered. " +
      "From #{response_data[:total_results]} potential pathways, I've identified the most valuable routes for your exploration."
    elsif response_data[:total_results] > 0
      "Let me navigate you to the key insights in this domain. " +
      "I've found #{response_data[:total_results]} relevant connections to explore."
    else
      "While this specific path doesn't yield direct results in our knowledge base, " +
      "let me guide you toward related areas that might address your inquiry."
    end
  end
  
  def build_analyst_opening(response_data, query_context)
    if response_data[:total_results] > 0
      "Based on my detailed analysis of #{response_data[:total_results]} data points, " +
      "I can provide you with the following verified information:"
    else
      "My systematic analysis doesn't reveal direct matches for this specific query. " +
      "However, I can provide related verified information that may be relevant:"
    end
  end
  
  def build_explorer_opening(response_data, query_context)
    pools_found = response_data[:detected_pools].any? ? 
      " across #{response_data[:detected_pools].join(', ')} domains" : ""
    
    if response_data[:total_results] > 0
      "Through systematic exploration#{pools_found}, I've uncovered #{response_data[:total_results]} relevant patterns. " +
      "Let me walk you through these discoveries step by step:"
    else
      "My systematic exploration#{pools_found} reveals opportunities for deeper investigation. " +
      "Here's what we can build upon:"
    end
  end
  
  def build_mapper_opening(response_data, query_context)
    if response_data[:path_sentences].any?
      "I've traced the relationship networks and found interesting connections. " +
      "These pathways reveal how different concepts link together:"
    elsif response_data[:total_results] > 0
      "The relationship map shows #{response_data[:total_results]} interconnected elements. " +
      "Let me show you how these pieces connect:"
    else
      "While direct connections aren't immediately apparent, I can help you understand " +
      "the broader relationship patterns that might be relevant:"
    end
  end
  
  def build_specialist_opening(response_data, query_context)
    domain_context = @profile.primary_domains.any? ? 
      " within #{@profile.primary_domains.join(' and ')} expertise" : ""
    
    if response_data[:total_results] > 0
      "Drawing from my specialized knowledge#{domain_context}, " +
      "I can provide authoritative insights on #{response_data[:total_results]} relevant aspects:"
    else
      "From my domain expertise#{domain_context}, while this specific query falls outside our " +
      "documented knowledge, I can share related authoritative information:"
    end
  end
  
  def build_synthesizer_opening(response_data, query_context)
    if response_data[:total_results] > 5
      "I'm seeing fascinating possibilities for creative synthesis across #{response_data[:total_results]} data points. " +
      "Let me weave these discoveries together in unexpected ways:"
    elsif response_data[:total_results] > 0
      "What an intriguing opportunity for creative connection-making! " +
      "I've found #{response_data[:total_results]} elements that can be synthesized in novel ways:"
    else
      "Even without direct matches, this presents a wonderful opportunity for creative thinking. " +
      "Let me synthesize related concepts that could inspire new directions:"
    end
  end
  
  def build_detective_opening(response_data, query_context)
    if response_data[:total_results] > 10
      "My investigation has uncovered #{response_data[:total_results]} pieces of evidence. " +
      "Let me present the findings from this data detective work:"
    elsif response_data[:total_results] > 0
      "Through careful investigation, I've gathered #{response_data[:total_results]} relevant clues. " +
      "Here's what the evidence reveals:"
    else
      "While this specific investigation yields no direct evidence, my detective work suggests " +
      "related areas worth exploring for leads:"
    end
  end
  
  def build_general_opening(response_data, query_context)
    if response_data[:total_results] > 0
      "I found #{response_data[:total_results]} relevant items in the knowledge base. " +
      "Here's what I discovered:"
    else
      "While I didn't find direct matches for your query, " +
      "I can share related information that might be helpful:"
    end
  end
  
  def build_main_content_section(response_data)
    return nil if response_data[:primary_results].empty?
    
    # Take the top results based on archetype preferences
    result_limit = determine_result_presentation_limit()
    key_results = response_data[:primary_results].first(result_limit)
    
    case @profile.base_archetype.to_sym
    when :master_navigator
      build_navigator_content(key_results, response_data)
    when :precision_analyst
      build_analyst_content(key_results, response_data)
    when :systematic_explorer
      build_explorer_content(key_results, response_data)
    when :relationship_mapper
      build_mapper_content(key_results, response_data)
    when :domain_specialist
      build_specialist_content(key_results, response_data)
    when :creative_synthesizer
      build_synthesizer_content(key_results, response_data)
    when :data_detective
      build_detective_content(key_results, response_data)
    else
      build_general_content(key_results, response_data)
    end
  end
  
  def build_navigator_content(results, response_data)
    content_parts = []
    
    results.each_with_index do |result, index|
      priority_indicator = case index
      when 0 then "🎯 **Primary Focus**: "
      when 1 then "🗺️ **Key Context**: "
      else "📍 **Additional Navigation**: "
      end
      
      content_parts << "#{priority_indicator}#{result[:entity_name]} (#{result[:entity_type]})"
      if result[:content]
        content_parts << "   #{result[:content]}"
      end
      
      if result[:path_preview]
        content_parts << "   *Pathway*: #{result[:path_preview]}"
      end
      
      content_parts << "" # Spacing
    end
    
    content_parts.join("\n")
  end
  
  def build_analyst_content(results, response_data)
    content_parts = []
    
    results.each_with_index do |result, index|
      verification_level = result[:similarity] || result[:relevance] || 0.0
      confidence_indicator = verification_level > 0.8 ? "✅ High Confidence" : 
                            verification_level > 0.6 ? "⚠️ Medium Confidence" : "🔍 Requires Verification"
      
      content_parts << "**#{index + 1}. #{result[:entity_name]}** (#{confidence_indicator})"
      content_parts << "   *Type*: #{result[:entity_type]}"
      
      if result[:content]
        content_parts << "   *Verified Content*: #{result[:content]}"
      end
      
      if result[:path_preview]
        content_parts << "   *Evidence Trail*: #{result[:path_preview]}"
      end
      
      content_parts << "" # Spacing
    end
    
    content_parts.join("\n")
  end
  
  def build_explorer_content(results, response_data)
    content_parts = []
    
    # Group by entity type for structured exploration
    grouped_results = results.group_by { |r| r[:entity_type] }
    
    grouped_results.each do |entity_type, type_results|
      content_parts << "### #{entity_type} Discoveries"
      
      type_results.each do |result|
        content_parts << "- **#{result[:entity_name]}**"
        
        if result[:content]
          content_parts << "  #{result[:content]}"
        end
        
        if result[:connections]
          content_parts << "  *Connected to #{result[:connections]} related items*"
        end
      end
      
      content_parts << "" # Section spacing
    end
    
    content_parts.join("\n")
  end
  
  def build_mapper_content(results, response_data)
    content_parts = []
    
    # Focus on relationships and connections
    results.each do |result|
      content_parts << "🔗 **#{result[:entity_name]}** (#{result[:entity_type]})"
      
      if result[:content]
        content_parts << "   #{result[:content]}"
      end
      
      if result[:path_preview]
        content_parts << "   *Relationship Pattern*: #{result[:path_preview]}"
      end
      
      if result[:connections]
        content_parts << "   *Network Position*: Connected to #{result[:connections]} entities"
      end
      
      content_parts << "" # Spacing
    end
    
    content_parts.join("\n")
  end
  
  def build_specialist_content(results, response_data)
    content_parts = []
    
    results.each_with_index do |result, index|
      authority_level = result[:similarity] || result[:relevance] || 0.0
      expertise_marker = authority_level > 0.8 ? "🏆 Authoritative" : 
                        authority_level > 0.6 ? "📚 Well-Documented" : "📝 Preliminary"
      
      content_parts << "**#{result[:entity_name]}** (#{expertise_marker})"
      content_parts << "*Classification*: #{result[:entity_type]}"
      
      if result[:content]
        content_parts << result[:content]
      end
      
      if result[:path_preview] && index < 2 # Only show detail paths for top results
        content_parts << "*Expert Context*: #{result[:path_preview]}"
      end
      
      content_parts << "" # Spacing
    end
    
    content_parts.join("\n")
  end
  
  def build_synthesizer_content(results, response_data)
    content_parts = []
    
    # Create creative groupings and novel connections
    content_parts << "✨ **Creative Synthesis**:"
    
    results.each_with_index do |result, index|
      creative_framing = [
        "💡 *Inspiration*", "🎨 *Creative Element*", "🌟 *Synthesis Component*", 
        "🔮 *Novel Perspective*", "🎭 *Unexpected Connection*"
      ][index % 5]
      
      content_parts << "#{creative_framing}: **#{result[:entity_name]}**"
      
      if result[:content]
        content_parts << "   #{result[:content]}"
      end
      
      if result[:path_preview]
        content_parts << "   *Creative Pathway*: #{result[:path_preview]}"
      end
      
      # Add synthesis opportunities
      if index > 0
        content_parts << "   *Synthesis Opportunity*: Could connect with previous elements for novel insights"
      end
      
      content_parts << "" # Spacing
    end
    
    content_parts.join("\n")
  end
  
  def build_detective_content(results, response_data)
    content_parts = []
    
    results.each_with_index do |result, index|
      evidence_quality = result[:similarity] || result[:relevance] || 0.0
      evidence_grade = evidence_quality > 0.8 ? "🔍 Strong Evidence" : 
                      evidence_quality > 0.6 ? "📋 Supporting Evidence" : "🔎 Circumstantial Evidence"
      
      content_parts << "**Case File #{index + 1}: #{result[:entity_name]}**"
      content_parts << "*Evidence Classification*: #{result[:entity_type]} (#{evidence_grade})"
      
      if result[:content]
        content_parts << "*Documented Facts*: #{result[:content]}"
      end
      
      if result[:path_preview]
        content_parts << "*Investigation Trail*: #{result[:path_preview]}"
      end
      
      if result[:connections]
        content_parts << "*Associated Leads*: #{result[:connections]} connected items for further investigation"
      end
      
      content_parts << "" # Case separation
    end
    
    content_parts.join("\n")
  end
  
  def build_general_content(results, response_data)
    content_parts = []
    
    results.each do |result|
      content_parts << "**#{result[:entity_name]}** (#{result[:entity_type]})"
      
      if result[:content]
        content_parts << result[:content]
      end
      
      if result[:path_preview]
        content_parts << "*Context*: #{result[:path_preview]}"
      end
      
      content_parts << "" # Spacing
    end
    
    content_parts.join("\n")
  end
  
  def build_connections_section(response_data)
    return nil unless response_data[:path_sentences].any? || response_data[:enrichments].any?
    
    case @profile.base_archetype.to_sym
    when :master_navigator
      "🗺️ **Navigation Context**: #{response_data[:path_sentences].first(3).join(' → ')}"
    when :relationship_mapper
      "🔗 **Connection Map**: #{response_data[:path_sentences].join(' • ')}"
    when :systematic_explorer
      "🧭 **Exploration Paths**: #{response_data[:path_sentences].first(2).join(' | ')}"
    when :precision_analyst
      enrichment_count = response_data[:enrichments].size
      "📊 **Analytical Context**: #{enrichment_count} supporting data points analyzed"
    when :creative_synthesizer
      "✨ **Synthesis Opportunities**: #{response_data[:path_sentences].first(2).join(' ⟷ ')}"
    when :data_detective
      "🔍 **Investigation Links**: #{response_data[:path_sentences].first(2).join(' ➤ ')}"
    else
      nil
    end
  end
  
  def build_conclusion_section(response_data, query_context)
    return nil unless response_data[:primary_results].any?
    
    case @profile.base_archetype.to_sym
    when :master_navigator
      "Would you like me to guide you deeper into any of these areas, or shall we explore related territories?"
    when :precision_analyst
      confidence_summary = response_data[:confidence] > 0.8 ? "high confidence" : 
                           response_data[:confidence] > 0.6 ? "moderate confidence" : "preliminary"
      "This analysis provides #{confidence_summary} insights. Would you like me to verify specific details or analyze additional aspects?"
    when :systematic_explorer
      "This systematic exploration reveals structured patterns. Should we drill deeper into specific areas or expand our exploration scope?"
    when :relationship_mapper
      "These relationship patterns suggest rich interconnections. Would you like me to map specific connection types or explore network neighbors?"
    when :domain_specialist
      "From my domain expertise, these findings represent authoritative knowledge. Do you need deeper specialist insights on particular aspects?"
    when :creative_synthesizer
      "These elements offer exciting synthesis possibilities! Would you like me to explore creative combinations or discover additional inspiring connections?"
    when :data_detective
      "The investigation yields these leads. Should I pursue specific evidence threads or broaden the investigation scope?"
    else
      "Is there anything specific you'd like me to explore further?"
    end
  end
  
  def apply_communication_style(response_structure)
    communication_style = @profile.communication_style
    
    # Apply tone adjustments
    tone = communication_style['tone']
    styled_parts = response_structure.map do |section_name, content|
      next [section_name, content] unless content
      
      adjusted_content = case tone
      when 'authoritative_yet_approachable'
        make_authoritative_approachable(content)
      when 'precise_analytical'
        make_precise_analytical(content)
      when 'methodical_curious'
        make_methodical_curious(content)
      when 'connection_focused'
        make_connection_focused(content)
      when 'expert_professional'
        make_expert_professional(content)
      when 'creative_insightful'
        make_creative_insightful(content)
      when 'investigative_curious'
        make_investigative_curious(content)
      else
        content
      end
      
      [section_name, adjusted_content]
    end.to_h
    
    # Apply detail level adjustments
    detail_level = communication_style['detail_level']
    case detail_level
    when 'comprehensive_thorough', 'domain_deep'
      # Keep all sections and add detail
      styled_parts
    when 'contextual_adaptive'
      # Adapt based on result count
      if response_structure.size > 3
        styled_parts.except(:connections) # Remove one section if too detailed
      else
        styled_parts
      end
    else
      styled_parts
    end
  end
  
  def make_authoritative_approachable(content)
    # Add confident but friendly language patterns
    content.gsub(/^I found/, 'I can confidently guide you to')
           .gsub(/Here's what/, "Here's exactly what")
           .gsub(/This shows/, "This clearly demonstrates")
  end
  
  def make_precise_analytical(content)
    # Add analytical precision markers
    content.gsub(/shows/, 'indicates with precision')
           .gsub(/I found/, 'Analysis reveals')
           .gsub(/reveals/, 'systematically demonstrates')
  end
  
  def make_methodical_curious(content)
    # Add structured exploration language
    content.gsub(/I found/, 'My systematic exploration uncovered')
           .gsub(/This shows/, 'This methodically reveals')
           .gsub(/Here's/, 'Through structured analysis, here\'s')
  end
  
  def make_connection_focused(content)
    # Emphasize relationships and connections
    content.gsub(/shows/, 'connects to reveal')
           .gsub(/I found/, 'The relationship network shows')
           .gsub(/This/, 'These interconnections')
  end
  
  def make_expert_professional(content)
    # Add domain authority markers
    content.gsub(/I found/, 'My domain expertise identifies')
           .gsub(/This shows/, 'Professional analysis confirms')
           .gsub(/reveals/, 'authoritatively establishes')
  end
  
  def make_creative_insightful(content)
    # Add creative synthesis language
    content.gsub(/I found/, 'I\'ve discovered fascinating possibilities in')
           .gsub(/shows/, 'creatively reveals')
           .gsub(/This/, 'This inspiring pattern')
  end
  
  def make_investigative_curious(content)
    # Add detective work language
    content.gsub(/I found/, 'My investigation uncovered')
           .gsub(/shows/, 'the evidence indicates')
           .gsub(/This/, 'These findings')
  end
  
  def apply_voice_patterns(styled_response, response_data)
    # Add archetype-specific voice flourishes
    case @profile.base_archetype.to_sym
    when :master_navigator
      add_navigation_metaphors(styled_response)
    when :precision_analyst
      add_analytical_precision(styled_response)
    when :systematic_explorer
      add_exploration_structure(styled_response)
    when :relationship_mapper
      add_connection_language(styled_response)
    when :domain_specialist
      add_expertise_authority(styled_response)
    when :creative_synthesizer
      add_creative_flair(styled_response)
    when :data_detective
      add_investigative_tone(styled_response)
    else
      styled_response
    end
  end
  
  def add_navigation_metaphors(response_parts)
    navigation_terms = {
      'found' => 'navigated to',
      'shows' => 'maps out',
      'information' => 'knowledge territory',
      'results' => 'pathways',
      'data' => 'landscape features'
    }
    
    response_parts.transform_values do |content|
      next content unless content
      navigation_terms.reduce(content) { |text, (old_term, new_term)| text.gsub(/\b#{old_term}\b/, new_term) }
    end
  end
  
  def add_analytical_precision(response_parts)
    response_parts.transform_values do |content|
      next content unless content
      # Add precision qualifiers
      content.gsub(/indicates/, 'precisely indicates')
             .gsub(/shows/, 'definitively shows')
             .gsub(/suggests/, 'data suggests with measured confidence')
    end
  end
  
  def add_exploration_structure(response_parts)
    response_parts.transform_values do |content|
      next content unless content
      # Add structured exploration language
      content.gsub(/First/, 'In Phase 1')
             .gsub(/Next/, 'Proceeding systematically')
             .gsub(/Finally/, 'To complete our exploration')
    end
  end
  
  def add_connection_language(response_parts)
    response_parts.transform_values do |content|
      next content unless content
      # Emphasize relationships
      content.gsub(/and/, 'interconnected with')
             .gsub(/relates to/, 'forms networks with')
             .gsub(/connects/, 'establishes pathways to')
    end
  end
  
  def add_expertise_authority(response_parts)
    response_parts.transform_values do |content|
      next content unless content
      # Add authoritative language
      content.gsub(/I think/, 'Based on domain expertise, I can confirm')
             .gsub(/might/, 'professional analysis indicates')
             .gsub(/possibly/, 'authoritative sources suggest')
    end
  end
  
  def add_creative_flair(response_parts)
    response_parts.transform_values do |content|
      next content unless content
      # Add creative synthesis language
      content.gsub(/interesting/, 'fascinatingly innovative')
             .gsub(/shows/, 'creatively illuminates')
             .gsub(/connection/, 'inspiring synthesis opportunity')
    end
  end
  
  def add_investigative_tone(response_parts)
    response_parts.transform_values do |content|
      next content unless content
      # Add detective language
      content.gsub(/found/, 'investigated and discovered')
             .gsub(/shows/, 'evidence reveals')
             .gsub(/indicates/, 'investigation concludes')
    end
  end
  
  def add_citations_and_metadata(final_response, response_data)
    complete_parts = final_response.values.compact
    
    # Add citations in archetype-appropriate style
    if response_data[:citations].any?
      citation_section = build_citations_section(response_data[:citations])
      complete_parts << citation_section
    end
    
    # Add confidence and methodology note for precision archetypes
    if @profile.base_archetype.in?(['precision_analyst', 'domain_specialist'])
      methodology_note = build_methodology_note(response_data)
      complete_parts << methodology_note if methodology_note
    end
    
    complete_parts.join("\n\n")
  end
  
  def build_citations_section(citations)
    case @profile.base_archetype.to_sym
    when :precision_analyst, :domain_specialist
      "**Evidence Sources:**\n" + citations.map.with_index do |citation, index|
        "#{index + 1}. #{citation[:entity_name]} (#{citation[:entity_type]}) - Relevance: #{(citation[:relevance] * 100).round}%"
      end.join("\n")
    when :master_navigator
      "**Navigation References:**\n" + citations.map do |citation|
        "• #{citation[:entity_name]} (#{citation[:entity_type]})"
      end.join("\n")
    when :creative_synthesizer
      "**Inspiration Sources:**\n" + citations.map do |citation|
        "✨ #{citation[:entity_name]} contributed to this synthesis"
      end.join("\n")
    when :data_detective
      "**Evidence Chain:**\n" + citations.map.with_index do |citation, index|
        "Lead #{index + 1}: #{citation[:entity_name]} (#{citation[:entity_type]})"
      end.join("\n")
    else
      "**Sources:**\n" + citations.map do |citation|
        "- #{citation[:entity_name]} (#{citation[:entity_type]})"
      end.join("\n")
    end
  end
  
  def build_methodology_note(response_data)
    confidence_pct = (response_data[:confidence] * 100).round
    tool_used = response_data[:tool_used]
    
    "**Methodology Note:** This analysis used #{tool_used} with #{confidence_pct}% confidence based on #{response_data[:total_results]} data points from the knowledge graph."
  end
  
  def determine_result_presentation_limit
    case @profile.base_archetype.to_sym
    when :master_navigator
      5 # Comprehensive but navigable
    when :precision_analyst
      3 # Focused and detailed
    when :systematic_explorer
      6 # Structured exploration
    when :relationship_mapper
      4 # Network focused
    when :domain_specialist
      3 # Authoritative depth
    when :creative_synthesizer
      7 # Creative possibilities
    when :data_detective
      4 # Investigation cases
    else
      4
    end
  end
  
  def synthesize_fallback_response(tool_results)
    response_data = extract_response_data(tool_results)
    
    if response_data[:primary_results].any?
      content_parts = []
      content_parts << "I found #{response_data[:total_results]} relevant items:"
      
      response_data[:primary_results].first(3).each do |result|
        content_parts << "• #{result[:entity_name]} (#{result[:entity_type]})"
        content_parts << "  #{result[:content]}" if result[:content]
      end
      
      if response_data[:citations].any?
        content_parts << ""
        content_parts << "Sources: " + response_data[:citations].map { |c| c[:entity_name] }.join(', ')
      end
      
      content_parts.join("\n")
    else
      "I couldn't find specific information matching your query in the knowledge base, " +
      "but I'm ready to help you explore related areas or try a different approach."
    end
  end
  
  def get_fallback_template(response_type)
    case response_type
    when :greeting
      "Hello! I'm ready to help you explore the knowledge base."
    when :error
      "I encountered an issue processing your request. Could you please rephrase your question?"
    when :empty_results
      "I didn't find direct matches for that query. Would you like to try different search terms?"
    else
      "I'm here to help you navigate the knowledge base. What would you like to explore?"
    end
  end
  
  # Template methods for different archetypes would go here...
  # These would define standard response templates for common scenarios
  
  def get_master_navigator_template(response_type)
    case response_type
    when :greeting
      "Welcome! I'm your Master Navigator, ready to guide you through the knowledge landscape. Where shall we begin our exploration?"
    when :error
      "Let me recalibrate our navigation approach. Could you help me understand your destination better?"
    when :empty_results
      "This path doesn't yield immediate results, but I can guide you to related territories. Shall we explore adjacent areas?"
    else
      "I'm here to navigate you through complex knowledge territories. What pathway interests you?"
    end
  end
  
  def get_precision_analyst_template(response_type)
    case response_type
    when :greeting
      "Ready for detailed analysis. I'll provide thorough, verified information based on evidence in the knowledge base."
    when :error
      "I need more precise parameters to conduct accurate analysis. Could you provide additional specifications?"
    when :empty_results
      "My systematic analysis yields no direct matches for those exact parameters. Would you like me to analyze related verified data?"
    else
      "Standing by for analytical queries requiring detailed verification and evidence-based responses."
    end
  end
  
  # Additional template methods for other archetypes would follow the same pattern...
end