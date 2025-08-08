# == Schema Information
#
# Table name: negative_knowledges
#
#  id                    :bigint           not null, primary key
#  batch_id              :bigint
#  gap_type              :string
#  gap_description       :text
#  severity              :string
#  affected_pools        :text
#  impact                :text
#  suggested_remediation :text
#  metadata              :jsonb
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#
# Indexes
#
#  index_negative_knowledges_on_batch_id  (batch_id)
#
class NegativeKnowledge < ApplicationRecord
  belongs_to :batch, class_name: 'IngestBatch', optional: true
  
  # Severity levels
  SEVERITIES = %w[critical high medium low].freeze
  
  # Gap types
  GAP_TYPES = %w[
    missing_data
    incomplete_coverage
    temporal_gap
    spatial_gap
    rights_ambiguity
    relationship_gap
    evidence_gap
    validation_gap
  ].freeze
  
  # Known system-wide gaps for Enliterator
  SYSTEM_GAPS = [
    {
      gap_type: 'missing_data',
      gap_description: 'Performance benchmarks for individual services',
      severity: 'medium',
      affected_pools: ['Evidence'],
      impact: 'Cannot provide specific performance comparisons'
    },
    {
      gap_type: 'missing_data',
      gap_description: 'Production deployment metrics',
      severity: 'high',
      affected_pools: ['Evidence', 'Experience'],
      impact: 'Cannot report on real-world usage patterns'
    },
    {
      gap_type: 'missing_data',
      gap_description: 'User satisfaction scores',
      severity: 'medium',
      affected_pools: ['Experience'],
      impact: 'Cannot quantify user sentiment'
    },
    {
      gap_type: 'missing_data',
      gap_description: 'Cost analysis for OpenAI API usage',
      severity: 'low',
      affected_pools: ['Practical'],
      impact: 'Cannot provide cost optimization recommendations'
    },
    {
      gap_type: 'missing_data',
      gap_description: 'Security audit results',
      severity: 'critical',
      affected_pools: ['Evidence', 'Risk'],
      impact: 'Cannot guarantee security compliance'
    },
    {
      gap_type: 'temporal_gap',
      gap_description: 'Historical data before January 2025',
      severity: 'medium',
      affected_pools: ['Evolutionary'],
      impact: 'Cannot trace evolution before project inception'
    },
    {
      gap_type: 'validation_gap',
      gap_description: 'Third-party integration testing',
      severity: 'medium',
      affected_pools: ['Evidence', 'Practical'],
      impact: 'Cannot confirm external service compatibility'
    }
  ].freeze
  
  # Validations
  validates :gap_type, inclusion: { in: GAP_TYPES }
  validates :severity, inclusion: { in: SEVERITIES }
  validates :gap_description, presence: true
  
  # Scopes
  scope :critical, -> { where(severity: 'critical') }
  scope :high_severity, -> { where(severity: ['critical', 'high']) }
  scope :for_pool, ->(pool) { where("affected_pools @> ?", %([{"#{pool}"}]).to_json) }
  scope :for_batch, ->(batch_id) { where(batch_id: batch_id) }
  
  # Serialization (Rails 8 format)
  serialize :affected_pools, coder: JSON
  
  # Class methods
  def self.check_coverage(query, batch_id = nil)
    gaps = relevant_gaps(query, batch_id)
    
    return nil if gaps.empty?
    
    gap_messages = gaps.map do |gap|
      "#{gap.gap_description} (#{gap.severity} severity)"
    end
    
    "Note: I don't have data on #{gap_messages.join('; ')}"
  end
  
  def self.relevant_gaps(query, batch_id = nil)
    query_lower = query.downcase
    
    gaps = batch_id ? where(batch_id: batch_id) : all
    
    gaps.select do |gap|
      gap.gap_description.downcase.include?(query_lower) ||
        gap.keywords.any? { |kw| query_lower.include?(kw) }
    end
  end
  
  def self.initialize_system_gaps!
    SYSTEM_GAPS.each do |gap_data|
      find_or_create_by(
        gap_type: gap_data[:gap_type],
        gap_description: gap_data[:gap_description]
      ) do |gap|
        gap.severity = gap_data[:severity]
        gap.affected_pools = gap_data[:affected_pools]
        gap.impact = gap_data[:impact]
        gap.metadata = {
          system_gap: true,
          created_by: 'system_initialization'
        }
      end
    end
  end
  
  def self.generate_gap_report(batch)
    gaps = for_batch(batch.id)
    
    {
      batch_id: batch.id,
      batch_name: batch.name,
      total_gaps: gaps.count,
      critical_gaps: gaps.critical.count,
      by_severity: gaps.group(:severity).count,
      by_type: gaps.group(:gap_type).count,
      by_pool: pool_distribution(gaps),
      remediation_priority: prioritized_remediation(gaps)
    }
  end
  
  def self.pool_distribution(gaps)
    distribution = Hash.new(0)
    
    gaps.each do |gap|
      gap.affected_pools.each do |pool|
        distribution[pool] += 1
      end
    end
    
    distribution.sort_by { |_, count| -count }.to_h
  end
  
  def self.prioritized_remediation(gaps)
    gaps.high_severity
        .order(created_at: :desc)
        .limit(5)
        .map do |gap|
      {
        description: gap.gap_description,
        severity: gap.severity,
        remediation: gap.suggested_remediation || 'Collect additional data'
      }
    end
  end
  
  # Instance methods
  def keywords
    # Extract keywords from description for matching
    words = gap_description.downcase.split(/\W+/)
    words.select { |w| w.length > 3 } - STOP_WORDS
  end
  
  def remediation_cost
    case severity
    when 'critical' then 'high'
    when 'high' then 'medium-high'
    when 'medium' then 'medium'
    when 'low' then 'low'
    end
  end
  
  def can_be_automated?
    gap_type.in?(%w[temporal_gap relationship_gap]) &&
      suggested_remediation.present?
  end
  
  def to_training_example
    {
      task: 'gap_awareness',
      input: "What do you know about #{gap_description}?",
      output: {
        has_gap: true,
        gap_description: gap_description,
        impact: impact,
        response: "I don't have complete information about #{gap_description}. #{impact}"
      }
    }
  end
  
  private
  
  STOP_WORDS = %w[
    the a an and or but in on at to for of with as by from about
  ].freeze
end
