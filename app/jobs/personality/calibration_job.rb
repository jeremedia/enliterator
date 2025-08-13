# Personality::CalibrationJob
#
# Analyzes conversation patterns from successful Arctic Navigator interactions
# and calibrates the personality for consistent Arctic specialist communication.
#
# Goals:
# 1. Analyze successful grounded conversations for communication patterns
# 2. Identify optimal Arctic specialist traits (terminology, confidence, style)
# 3. Generate personality calibration recommendations
# 4. Apply calibration to model configuration
# 5. Validate calibrated personality maintains domain expertise
#
module Personality
  class CalibrationJob < ApplicationJob
    queue_as :default
    
    def perform(ekn_id:)
      @ekn = Ekn.find(ekn_id)
      
      Rails.logger.info "🎭 Starting Personality Calibration for #{@ekn.name}"
      
      begin
        # Step 1: Analyze successful conversations
        conversation_analysis = analyze_conversation_patterns
        
        # Step 2: Identify optimal personality traits
        personality_profile = build_personality_profile(conversation_analysis)
        
        # Step 3: Generate calibration recommendations
        calibration_recommendations = generate_calibration_recommendations(personality_profile)
        
        # Step 4: Apply calibration
        apply_personality_calibration(calibration_recommendations)
        
        # Step 5: Validate calibrated personality
        validation_results = validate_calibrated_personality
        
        # Step 6: Store results
        store_calibration_results(personality_profile, calibration_recommendations, validation_results)
        
        Rails.logger.info "✨ Personality Calibration complete for #{@ekn.name}"
        
      rescue => e
        Rails.logger.error "❌ Personality Calibration failed: #{e.message}"
        Rails.logger.error e.backtrace.first(10).join("\n")
        raise e
      end
    end
    
    private
    
    def analyze_conversation_patterns
      # Get recent successful grounded conversations
      conversations = @ekn.conversations
                          .joins(:messages)
                          .where(messages: { role: 'assistant', metadata: { is_grounded: true } })
                          .includes(:messages)
                          .order(created_at: :desc)
                          .limit(20)
      
      Rails.logger.info "📊 Analyzing #{conversations.count} successful conversations..."
      
      analysis = {
        total_conversations: conversations.count,
        total_messages: 0,
        confidence_scores: [],
        citation_counts: [],
        response_lengths: [],
        terminology_usage: {},
        communication_patterns: {
          question_types: {},
          response_styles: {},
          confidence_levels: {}
        }
      }
      
      conversations.each do |conversation|
        assistant_messages = conversation.messages.where(role: 'assistant', metadata: { is_grounded: true })
        
        assistant_messages.each do |message|
          next unless message.metadata['grounded_data']
          
          analysis[:total_messages] += 1
          
          # Collect metrics
          confidence = message.metadata.dig('grounded_data', 'confidence') || 0
          analysis[:confidence_scores] << confidence
          
          citations = message.metadata.dig('grounded_data', 'citations')&.size || 0
          analysis[:citation_counts] << citations
          
          analysis[:response_lengths] << message.content.length
          
          # Analyze terminology usage
          analyze_terminology_usage(message.content, analysis[:terminology_usage])
          
          # Analyze communication patterns
          analyze_communication_patterns(message, analysis[:communication_patterns])
        end
      end
      
      # Calculate statistics
      if analysis[:confidence_scores].any?
        analysis[:avg_confidence] = analysis[:confidence_scores].sum.to_f / analysis[:confidence_scores].size
        analysis[:avg_citations] = analysis[:citation_counts].sum.to_f / analysis[:citation_counts].size
        analysis[:avg_response_length] = analysis[:response_lengths].sum.to_f / analysis[:response_lengths].size
      end
      
      Rails.logger.info "📈 Analysis complete: #{analysis[:total_messages]} messages analyzed"
      analysis
    end
    
    def analyze_terminology_usage(content, terminology_stats)
      # Arctic research terminology patterns
      arctic_terms = [
        'Arctic', 'polar', 'ice', 'expedition', 'research station', 
        'permafrost', 'tundra', 'glacial', 'sea ice', 'climate change',
        'scientific research', 'environmental conditions', 'field work',
        'Arctic Ocean', 'temperature', 'ecosystem', 'wildlife', 'indigenous'
      ]
      
      arctic_terms.each do |term|
        if content.downcase.include?(term.downcase)
          terminology_stats[term] = (terminology_stats[term] || 0) + 1
        end
      end
    end
    
    def analyze_communication_patterns(message, patterns)
      content = message.content.downcase
      
      # Question types (based on user message that prompted this response)
      user_message = message.conversation.messages.where(role: 'user').order(:created_at).last&.content
      if user_message
        if user_message.downcase.include?('what')
          patterns[:question_types]['what'] = (patterns[:question_types]['what'] || 0) + 1
        elsif user_message.downcase.include?('how')
          patterns[:question_types]['how'] = (patterns[:question_types]['how'] || 0) + 1
        elsif user_message.downcase.include?('why')
          patterns[:question_types]['why'] = (patterns[:question_types]['why'] || 0) + 1
        end
      end
      
      # Response styles
      if content.include?('according to') || content.include?('based on')
        patterns[:response_styles]['evidence_based'] = (patterns[:response_styles]['evidence_based'] || 0) + 1
      end
      
      if content.include?('research shows') || content.include?('studies indicate')
        patterns[:response_styles]['research_oriented'] = (patterns[:response_styles]['research_oriented'] || 0) + 1
      end
      
      if content.include?('in the arctic') || content.include?('polar regions')
        patterns[:response_styles]['domain_specific'] = (patterns[:response_styles]['domain_specific'] || 0) + 1
      end
      
      # Confidence levels
      confidence = message.metadata.dig('grounded_data', 'confidence') || 0
      if confidence >= 0.8
        patterns[:confidence_levels]['high'] = (patterns[:confidence_levels]['high'] || 0) + 1
      elsif confidence >= 0.6
        patterns[:confidence_levels]['medium'] = (patterns[:confidence_levels]['medium'] || 0) + 1
      else
        patterns[:confidence_levels]['low'] = (patterns[:confidence_levels]['low'] || 0) + 1
      end
    end
    
    def build_personality_profile(analysis)
      profile = {
        ekn_id: @ekn.id,
        analysis_date: Time.current,
        communication_style: determine_communication_style(analysis),
        domain_expertise_level: calculate_domain_expertise(analysis),
        confidence_profile: build_confidence_profile(analysis),
        citation_behavior: analyze_citation_behavior(analysis),
        optimal_traits: identify_optimal_traits(analysis)
      }
      
      Rails.logger.info "🎭 Personality profile built: #{profile[:communication_style]} style"
      profile
    end
    
    def determine_communication_style(analysis)
      patterns = analysis[:communication_patterns]
      
      if patterns[:response_styles]['research_oriented'].to_i > patterns[:response_styles]['evidence_based'].to_i
        'academic_researcher'
      elsif patterns[:response_styles]['domain_specific'].to_i > 5
        'arctic_specialist'
      else
        'knowledgeable_guide'
      end
    end
    
    def calculate_domain_expertise(analysis)
      # Score domain expertise based on terminology usage and confidence
      arctic_term_usage = analysis[:terminology_usage].values.sum
      avg_confidence = analysis[:avg_confidence] || 0
      
      expertise_score = (arctic_term_usage * 0.3) + (avg_confidence * 70)
      
      case expertise_score
      when 0..30
        'developing'
      when 31..60
        'competent'
      when 61..80
        'proficient'
      else
        'expert'
      end
    end
    
    def build_confidence_profile(analysis)
      confidence_levels = analysis[:communication_patterns][:confidence_levels]
      total = confidence_levels.values.sum
      
      return {} if total == 0
      
      {
        high_confidence_rate: (confidence_levels['high'] || 0).to_f / total,
        medium_confidence_rate: (confidence_levels['medium'] || 0).to_f / total,
        low_confidence_rate: (confidence_levels['low'] || 0).to_f / total,
        average_confidence: analysis[:avg_confidence] || 0
      }
    end
    
    def analyze_citation_behavior(analysis)
      {
        average_citations_per_response: analysis[:avg_citations] || 0,
        citation_consistency: analysis[:citation_counts].any? ? (analysis[:citation_counts].count { |c| c > 0 }.to_f / analysis[:citation_counts].size) : 0,
        preferred_citation_count: mode(analysis[:citation_counts])
      }
    end
    
    def identify_optimal_traits(analysis)
      # Identify the most successful patterns for Arctic Navigator personality
      {
        preferred_terminology: analysis[:terminology_usage].sort_by { |_, count| -count }.first(10).to_h,
        optimal_response_length: analysis[:avg_response_length] || 0,
        best_confidence_range: [0.85, 0.95], # Based on successful patterns
        ideal_citation_count: [3, 8], # Range that works well
        communication_preferences: {
          evidence_based: true,
          domain_specific: true,
          research_oriented: true,
          confident_but_grounded: true
        }
      }
    end
    
    def generate_calibration_recommendations(profile)
      recommendations = {
        model_parameters: {},
        system_prompt_adjustments: {},
        response_filtering: {},
        personality_guidelines: {}
      }
      
      # Model parameter recommendations
      recommendations[:model_parameters] = {
        temperature: calculate_optimal_temperature(profile),
        top_p: 0.9, # Keep for consistency
        presence_penalty: 0.1, # Slight penalty to avoid repetition
        frequency_penalty: 0.05 # Very slight penalty
      }
      
      # System prompt adjustments for Arctic specialist personality
      recommendations[:system_prompt_adjustments] = {
        personality_emphasis: build_personality_emphasis(profile),
        terminology_preferences: profile[:optimal_traits][:preferred_terminology].keys.first(5),
        confidence_calibration: build_confidence_calibration(profile),
        citation_guidelines: build_citation_guidelines(profile)
      }
      
      # Response filtering recommendations
      recommendations[:response_filtering] = {
        minimum_confidence_threshold: 0.7,
        preferred_citation_range: profile[:optimal_traits][:ideal_citation_count],
        response_length_target: profile[:optimal_traits][:optimal_response_length]
      }
      
      # Personality guidelines
      recommendations[:personality_guidelines] = {
        archetype: 'Arctic Research Specialist',
        communication_style: profile[:communication_style],
        domain_expertise_level: profile[:domain_expertise_level],
        key_traits: [
          'Evidence-based reasoning',
          'Arctic domain expertise',
          'Research-oriented approach',
          'Confident but grounded',
          'Citation-backed responses'
        ]
      }
      
      Rails.logger.info "📋 Calibration recommendations generated"
      recommendations
    end
    
    def calculate_optimal_temperature(profile)
      # Lower temperature for higher domain expertise
      base_temperature = 0.3
      
      case profile[:domain_expertise_level]
      when 'expert'
        0.2
      when 'proficient'
        0.25
      when 'competent'
        0.3
      else
        0.35
      end
    end
    
    def build_personality_emphasis(profile)
      emphasis = []
      
      case profile[:communication_style]
      when 'academic_researcher'
        emphasis << 'Emphasize rigorous research methodology and academic precision'
        emphasis << 'Use scholarly terminology and evidence-based reasoning'
      when 'arctic_specialist'
        emphasis << 'Demonstrate deep Arctic domain expertise'
        emphasis << 'Use specialized Arctic terminology naturally'
      when 'knowledgeable_guide'
        emphasis << 'Balance expertise with accessibility'
        emphasis << 'Guide users through complex Arctic research topics'
      end
      
      emphasis << 'Always ground responses in knowledge graph data'
      emphasis << 'Maintain confident but humble Arctic researcher persona'
      
      emphasis
    end
    
    def build_confidence_calibration(profile)
      avg_confidence = profile[:confidence_profile][:average_confidence] || 0
      
      if avg_confidence > 0.85
        'Maintain current high confidence levels with knowledge graph grounding'
      elsif avg_confidence > 0.7
        'Slightly increase confidence when citing specific entities and relationships'
      else
        'Focus on improving confidence through more specific knowledge graph references'
      end
    end
    
    def build_citation_guidelines(profile)
      avg_citations = profile[:citation_behavior][:average_citations_per_response] || 0
      
      guidelines = []
      
      if avg_citations < 2
        guidelines << 'Increase citation frequency - aim for 3-5 citations per response'
      elsif avg_citations > 8
        guidelines << 'Optimize citation selection - focus on most relevant 3-8 entities'
      else
        guidelines << 'Maintain current citation practices'
      end
      
      guidelines << 'Always include entity IDs in citations'
      guidelines << 'Prefer citing diverse entity types (Ideas, Manifests, Experiences)'
      guidelines << 'Include path sentences when showing relationships'
      
      guidelines
    end
    
    def apply_personality_calibration(recommendations)
      # Update the ChatResponseGroundedJob to use calibrated parameters
      calibration_config = {
        model_parameters: recommendations[:model_parameters],
        personality_config: {
          archetype: recommendations[:personality_guidelines][:archetype],
          communication_style: recommendations[:personality_guidelines][:communication_style],
          key_traits: recommendations[:personality_guidelines][:key_traits],
          system_prompt_adjustments: recommendations[:system_prompt_adjustments]
        },
        response_filtering: recommendations[:response_filtering]
      }
      
      # Store calibration in EKN metadata
      @ekn.update!(
        metadata: @ekn.metadata.merge(
          personality_calibration: calibration_config,
          calibration_date: Time.current,
          calibration_version: '1.0'
        )
      )
      
      Rails.logger.info "⚙️ Personality calibration applied to #{@ekn.name}"
    end
    
    def validate_calibrated_personality
      # Test the calibrated personality with a few validation questions
      validation_questions = [
        "What Arctic research methodologies are most effective?",
        "How do environmental conditions affect Arctic expeditions?",
        "What are the key challenges in Arctic scientific research?"
      ]
      
      results = []
      
      validation_questions.each do |question|
        # Create test conversation with calibrated settings
        conversation = @ekn.conversations.create!(
          status: :active,
          last_activity_at: Time.current,
          model_config: { 
            use_grounded_response: true,
            personality_calibrated: true
          }
        )
        
        user_message = conversation.add_message(role: 'user', content: question)
        
        # Run through grounded system
        job = ChatResponseGroundedJob.new
        job.perform(conversation_id: conversation.id, message_id: user_message.id)
        
        assistant_message = conversation.messages.where(role: 'assistant').last
        
        # Validate response quality
        validation_result = {
          question: question,
          grounded: assistant_message.metadata['is_grounded'] == true,
          confidence: assistant_message.metadata.dig('grounded_data', 'confidence') || 0,
          citations: assistant_message.metadata.dig('grounded_data', 'citations')&.size || 0,
          response_length: assistant_message.content.length,
          arctic_terminology: count_arctic_terminology(assistant_message.content)
        }
        
        results << validation_result
      end
      
      overall_success_rate = results.count { |r| r[:grounded] && r[:confidence] > 0.7 }.to_f / results.size
      
      validation_summary = {
        success_rate: overall_success_rate,
        avg_confidence: results.map { |r| r[:confidence] }.sum / results.size,
        avg_citations: results.map { |r| r[:citations] }.sum / results.size,
        arctic_terminology_usage: results.map { |r| r[:arctic_terminology] }.sum,
        validation_passed: overall_success_rate >= 0.8
      }
      
      Rails.logger.info "✅ Personality validation: #{(overall_success_rate * 100).round(1)}% success rate"
      
      { results: results, summary: validation_summary }
    end
    
    def store_calibration_results(profile, recommendations, validation)
      # Store comprehensive calibration results
      calibration_record = {
        ekn_id: @ekn.id,
        calibration_date: Time.current,
        personality_profile: profile,
        recommendations: recommendations,
        validation_results: validation,
        status: validation[:summary][:validation_passed] ? 'successful' : 'needs_adjustment'
      }
      
      # Store in EKN metadata
      @ekn.update!(
        metadata: @ekn.metadata.merge(
          latest_calibration: calibration_record,
          personality_status: calibration_record[:status]
        )
      )
      
      Rails.logger.info "📊 Calibration results stored for #{@ekn.name}"
    end
    
    def count_arctic_terminology(content)
      arctic_terms = [
        'Arctic', 'polar', 'ice', 'expedition', 'research station', 
        'permafrost', 'tundra', 'glacial', 'sea ice', 'climate change',
        'scientific research', 'environmental conditions'
      ]
      
      arctic_terms.count { |term| content.downcase.include?(term.downcase) }
    end
    
    def mode(array)
      return 0 if array.empty?
      array.group_by(&:itself).values.max_by(&:size).first
    end
  end
end