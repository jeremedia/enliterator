# frozen_string_literal: true

# Meta-Creation Assessment - Evaluates the meta-enliterator's effectiveness
#
# This model tracks and assesses how well the meta-enliterator is performing
# its core function: guiding users through the creation and evolution of
# effective, personalized Knowledge Navigators.
#
# Key assessment areas:
# - Creation Guidance Quality: Does the meta-enliterator help users create appropriate EKNs?
# - Personality Development: Are the resulting EKNs developing healthy, distinctive personalities?
# - User Satisfaction: Are users getting the knowledge navigators they need?
# - Meta-Learning: Is the meta-enliterator improving its creation abilities over time?
#
class MetaCreationAssessment < ApplicationRecord
  belongs_to :ekn  # The EKN that was created/guided
  belongs_to :mcp_test_run, optional: true  # Link to test that triggered assessment
  
  enum :assessment_type, {
    creation_guidance: 0,      # How well did meta-enliterator guide initial EKN creation?
    personality_development: 1, # Is the EKN developing a healthy personality?
    user_satisfaction: 2,      # Is the user getting value from this EKN?
    meta_learning: 3,          # Is meta-enliterator learning from this EKN's development?
    tuning_effectiveness: 4    # How well do personality adjustments work?
  }
  
  enum :assessment_status, {
    pending: 0,
    analyzing: 1,
    completed: 2,
    failed: 3
  }
  
  # JSON fields for comprehensive assessment data
  attribute :assessment_criteria, :json, default: {}
  attribute :evaluation_results, :json, default: {}
  attribute :meta_enliterator_performance, :json, default: {}
  attribute :personality_health_metrics, :json, default: {}
  attribute :user_satisfaction_indicators, :json, default: {}
  attribute :improvement_recommendations, :json, default: {}
  attribute :meta_learning_evidence, :json, default: {}
  
  validates :assessment_type, presence: true
  validates :overall_score, presence: true, inclusion: { in: 0.0..1.0 }
  
  scope :recent, -> { where(created_at: 1.month.ago..) }
  scope :by_type, ->(type) { where(assessment_type: type) }
  scope :high_performing, -> { where('overall_score >= ?', 0.8) }
  scope :needs_attention, -> { where('overall_score < ?', 0.6) }
  
  # Create comprehensive assessment of meta-enliterator performance
  def self.assess_meta_creation(ekn, assessment_type, context_data = {})
    assessment = create!(
      ekn: ekn,
      assessment_type: assessment_type,
      assessment_status: :analyzing,
      assessment_criteria: build_criteria_for_type(assessment_type),
      context_data: context_data
    )
    
    # Queue intelligent evaluation
    MetaCreationEvaluationJob.perform_later(assessment.id)
    assessment
  end
  
  # Get formatted summary for reports
  def assessment_summary
    {
      'ekn' => "#{ekn.slug} (##{ekn.id})",
      'type' => assessment_type.humanize,
      'overall_score' => overall_score,
      'status' => assessment_status,
      'key_findings' => evaluation_results&.dig('key_findings') || [],
      'recommendations' => improvement_recommendations&.dig('priority_items') || [],
      'meta_enliterator_effectiveness' => meta_enliterator_performance&.dig('effectiveness_score'),
      'assessed_at' => created_at.strftime('%Y-%m-%d %H:%M')
    }
  end
  
  # Check if this assessment indicates the meta-enliterator is improving
  def shows_meta_learning?
    return false unless meta_learning_evidence.present?
    
    evidence = meta_learning_evidence
    
    # Look for improvement indicators
    improvement_indicators = %w[
      guidance_quality_trend
      personality_development_success_rate
      user_satisfaction_trend
      creation_speed_improvement
    ]
    
    improvement_indicators.any? { |indicator| evidence[indicator] == 'improving' }
  end
  
  # Get specific recommendations for improving meta-enliterator performance
  def meta_improvement_recommendations
    return [] unless improvement_recommendations.present?
    
    recommendations = improvement_recommendations['meta_enliterator_specific'] || []
    recommendations.select { |rec| rec['priority'] == 'high' }
  end
  
  # Check if EKN personality development is healthy
  def healthy_personality_development?
    return false unless personality_health_metrics.present?
    
    metrics = personality_health_metrics
    
    # Check key health indicators
    consistency_score = metrics['consistency_score'] || 0.0
    evolution_rate = metrics['evolution_rate'] || 0.0
    distinctiveness_score = metrics['distinctiveness_score'] || 0.0
    
    # Healthy development: consistent, evolving appropriately, distinctive
    consistency_score >= 0.7 && 
    evolution_rate.between?(0.1, 0.4) && 
    distinctiveness_score >= 0.6
  end
  
  # Get context for intelligent evaluation agent
  def evaluation_context
    profile = ekn.ekn_personality_profile
    
    context = {
      'assessment_type' => assessment_type,
      'ekn_details' => {
        'id' => ekn.id,
        'slug' => ekn.slug,
        'created_at' => ekn.created_at,
        'total_items' => ekn.ingest_items.count,
        'active_since' => ekn.created_at
      },
      'personality_profile' => profile&.personality_summary,
      'assessment_criteria' => assessment_criteria,
      'context_data' => context_data || {}
    }
    
    # Add type-specific context
    case assessment_type.to_sym
    when :creation_guidance
      context['creation_context'] = extract_creation_context
    when :personality_development
      context['personality_evolution'] = profile&.evolution_history&.last(5) || []
    when :user_satisfaction
      context['interaction_patterns'] = extract_interaction_patterns
    when :meta_learning
      context['historical_assessments'] = extract_learning_evidence
    end
    
    context
  end
  
  private
  
  def self.build_criteria_for_type(assessment_type)
    criteria = {
      'framework_compliance' => 'Does the EKN properly use Ten Pool Canon and canonical naming?',
      'personality_authenticity' => 'Does the EKN have a distinctive, consistent personality?',
      'user_value_delivery' => 'Is the EKN providing value to its users?'
    }
    
    case assessment_type.to_sym
    when :creation_guidance
      criteria.merge!({
        'guidance_clarity' => 'Did meta-enliterator provide clear, helpful guidance?',
        'appropriate_personality_direction' => 'Did meta-enliterator suggest appropriate personality characteristics?',
        'creation_efficiency' => 'Was the EKN creation process efficient and smooth?'
      })
    when :personality_development
      criteria.merge!({
        'consistency_maintenance' => 'Is personality consistent across interactions?',
        'healthy_evolution' => 'Is personality evolving in beneficial ways?',
        'distinctiveness_preservation' => 'Does EKN maintain its unique characteristics?'
      })
    when :user_satisfaction
      criteria.merge!({
        'need_fulfillment' => 'Does EKN meet user\'s original needs?',
        'interaction_quality' => 'Are user-EKN interactions productive and satisfying?',
        'growth_together' => 'Are user and EKN growing together effectively?'
      })
    when :meta_learning
      criteria.merge!({
        'improvement_evidence' => 'Is meta-enliterator getting better at creation guidance?',
        'pattern_recognition' => 'Does meta-enliterator recognize what works well?',
        'adaptation_capability' => 'Can meta-enliterator adapt to different user needs?'
      })
    end
    
    criteria
  end
  
  def extract_creation_context
    # Get context about how this EKN was created
    {
      'creation_date' => ekn.created_at,
      'pipeline_completion_time' => calculate_pipeline_duration,
      'initial_data_sources' => ekn.ingest_batches.first&.ingest_items&.limit(5)&.pluck(:title) || [],
      'meta_guidance_quality' => 'unknown'  # Would be populated by meta-enliterator interaction data
    }
  end
  
  def extract_interaction_patterns
    # Get recent user interaction patterns
    recent_conversations = ekn.conversations.where(created_at: 1.month.ago..).includes(:messages)
    
    {
      'total_conversations' => recent_conversations.count,
      'avg_messages_per_conversation' => calculate_avg_messages(recent_conversations),
      'query_diversity' => assess_query_diversity(recent_conversations),
      'satisfaction_signals' => extract_satisfaction_signals(recent_conversations)
    }
  end
  
  def extract_learning_evidence
    # Get historical assessments to show meta-enliterator learning trends
    similar_ekns = Ekn.where.not(id: ekn.id).where(created_at: 6.months.ago..)
    assessments = MetaCreationAssessment.where(ekn: similar_ekns)
                                       .where(assessment_type: assessment_type)
                                       .order(created_at: :asc)
    
    {
      'trend_data' => assessments.pluck(:overall_score, :created_at),
      'improvement_indicators' => calculate_improvement_trends(assessments),
      'pattern_recognition_evidence' => extract_pattern_evidence(assessments)
    }
  end
  
  def calculate_pipeline_duration
    # Calculate how long it took to process this EKN through the pipeline
    first_batch = ekn.ingest_batches.order(created_at: :asc).first
    return nil unless first_batch
    
    # Simplified - would need more sophisticated pipeline stage tracking
    (ekn.created_at - first_batch.created_at) / 1.hour
  end
  
  def calculate_avg_messages(conversations)
    return 0 if conversations.empty?
    
    total_messages = conversations.sum { |conv| conv.messages.count }
    total_messages.to_f / conversations.count
  end
  
  def assess_query_diversity(conversations)
    # Simplified diversity assessment
    all_messages = conversations.flat_map(&:messages)
    unique_queries = all_messages.map(&:content).uniq.count
    total_queries = all_messages.count
    
    return 0.0 if total_queries.zero?
    unique_queries.to_f / total_queries
  end
  
  def extract_satisfaction_signals(conversations)
    # Look for satisfaction indicators in conversation patterns
    # This would be more sophisticated in practice
    {
      'repeat_usage' => conversations.count > 1,
      'conversation_length_trend' => 'stable',  # Would calculate actual trend
      'query_complexity_evolution' => 'increasing'  # Would analyze actual complexity
    }
  end
  
  def calculate_improvement_trends(assessments)
    return {} if assessments.count < 3
    
    scores = assessments.pluck(:overall_score)
    early_scores = scores.first(3).sum / 3.0
    recent_scores = scores.last(3).sum / 3.0
    
    {
      'overall_trend' => recent_scores > early_scores ? 'improving' : 'declining',
      'improvement_magnitude' => (recent_scores - early_scores).abs
    }
  end
  
  def extract_pattern_evidence(assessments)
    # Analyze if meta-enliterator is learning patterns about what works
    # This would be more sophisticated pattern analysis
    {
      'consistent_strengths' => ['framework_compliance', 'personality_development'],
      'improving_areas' => ['user_satisfaction', 'guidance_clarity'],
      'pattern_recognition_score' => 0.7
    }
  end
end