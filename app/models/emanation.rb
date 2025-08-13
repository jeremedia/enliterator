# frozen_string_literal: true

# == Schema Information
#
# Table name: emanations
#
#  id                       :bigint           not null, primary key
#  influence_type           :string           not null
#  target_context           :text
#  pathway                  :text
#  evidence                 :text
#  repr_text                :text             not null
#  provenance_and_rights_id :bigint           not null
#  valid_time_start         :datetime         not null
#  valid_time_end           :datetime
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  strength                 :float
#  evidence_refs            :jsonb
#  temporal_extent          :jsonb
#
# Indexes
#
#  index_emanations_on_influence_type                       (influence_type)
#  index_emanations_on_provenance_and_rights_id             (provenance_and_rights_id)
#  index_emanations_on_valid_time_start_and_valid_time_end  (valid_time_start,valid_time_end)
#
class Emanation < ApplicationRecord
  include EknPoolEntity

  # Enums for influence classification
  enum :influence_type, {
    cultural: "cultural",
    emotional: "emotional",
    practical: "practical",
    systemic: "systemic",
    environmental: "environmental",
    social: "social",
    economic: "economic",
    spiritual: "spiritual",
    aesthetic: "aesthetic",
    technological: "technological"
  }, prefix: true

  enum :impact_level, {
    negligible: 0,       # Minimal measurable effect
    minor: 1,           # Small but noticeable impact
    moderate: 2,        # Significant but contained effect
    significant: 3,     # Major impact across domains
    transformative: 4   # Fundamental change or revolution
  }, prefix: true

  enum :temporal_scope, {
    immediate: 0,       # Effects within days/weeks
    short_term: 1,      # Effects within months
    medium_term: 2,     # Effects within years
    long_term: 3,       # Effects within decades
    permanent: 4        # Lasting/irreversible effects
  }, prefix: true

  enum :evidence_quality, {
    anecdotal: 0,       # Stories, unverified reports
    observational: 1,   # Witnessed but undocumented
    documented: 2,      # Written records, evidence exists
    validated: 3,       # Cross-verified, multiple sources
    peer_reviewed: 4    # Scientific validation, published
  }, prefix: true

  enum :directness, {
    direct: 0,          # Immediate cause-effect relationship
    indirect: 1,        # Mediated through one intermediate
    cascading: 2,       # Chain reaction, multiple steps
    emergent: 3         # Unpredictable, system-level effect
  }, prefix: true

  # Model-driven extraction configuration
  extraction_config do
    canonical_name "Emanation"
    description "Ripple effects, influence patterns, secondary outcomes - systemic impact and diffusion tracking"
    
    field :influence_type, type: :enum,
      values: -> { influence_types.keys },  # Live from model enum - 10 values!
      default: 'cultural',
      hints: "cultural: traditions/beliefs; emotional: feelings/psychology; practical: tools/methods; systemic: structures/processes; environmental: ecosystem/climate; social: relationships/communities; economic: finance/markets; spiritual: meaning/purpose; aesthetic: beauty/design; technological: innovation/tools"
      
    field :impact_level, type: :enum,
      values: -> { impact_levels.keys },  # Live from model enum - 5 values!
      default: 'moderate',
      hints: "negligible: minimal effect; minor: small impact; moderate: significant but contained; significant: major cross-domain; transformative: fundamental change"
      
    field :temporal_scope, type: :enum,
      values: -> { temporal_scopes.keys },  # Live from model enum - 5 values!
      default: 'medium_term',
      hints: "immediate: days/weeks; short_term: months; medium_term: years; long_term: decades; permanent: irreversible"
      
    field :evidence_quality, type: :enum,
      values: -> { evidence_qualities.keys },  # Live from model enum - 5 values!
      default: 'documented',
      hints: "anecdotal: unverified stories; observational: witnessed; documented: written records; validated: cross-verified; peer_reviewed: scientific validation"
      
    field :directness, type: :enum,
      values: -> { directnesses.keys },  # Live from model enum - 4 values!
      default: 'direct',
      hints: "direct: immediate cause-effect; indirect: one intermediate step; cascading: chain reaction; emergent: unpredictable system effect"
      
    field :pathway, type: :text, required: true,
      examples: [
        "Climate research findings → Policy changes → Community adaptation strategies",
        "Burning Man principles → Regional community practices → Local governance models", 
        "Arctic data collection → International cooperation → Conservation agreements"
      ],
      hints: "Description of how the influence spreads or manifests - the causal pathway"
      
    field :target_context, type: :text, required: false,
      examples: [
        "Rural Alaskan communities adapting to climate change",
        "Urban planning incorporating participatory principles",
        "Scientific collaboration networks in polar research"
      ],
      hints: "The domain, community, or context where this influence is observed"
      
    field :strength, type: :float, required: false,
      examples: [0.85, 0.67, 0.42, 0.23],
      hints: "Quantitative measure of influence strength between 0.0 (weak) and 1.0 (maximum impact)"
      
    field :evidence_refs, type: :json, required: false,
      examples: [
        ["Study: Arctic Community Resilience 2023", "Report: Policy Impact Assessment"],
        ["Interview: Community Leader Johnson", "Document: Local Adaptation Plan"]
      ],
      hints: "Array of evidence sources, references, or documentation supporting this influence claim"
  end

  # Associations through join tables
  has_many :idea_emanations, dependent: :destroy
  has_many :ideas, through: :idea_emanations
  has_many :experience_emanations, dependent: :destroy
  has_many :experiences, through: :experience_emanations
  has_many :emanation_ideas, dependent: :destroy
  has_many :influenced_ideas, through: :emanation_ideas, source: :idea
  has_many :emanation_relationals, dependent: :destroy
  has_many :relationals, through: :emanation_relationals

  # Validations
  validates :influence_type, presence: true
  validates :pathway, presence: true
  validates :repr_text, presence: true, length: { maximum: 500 }
  validates :strength, numericality: { in: 0.0..1.0 }, allow_nil: true

  # Scopes
  scope :by_type, ->(type) { where(influence_type: type) }
  scope :strong_influences, -> { where("strength > ?", 0.7) }
  scope :weak_influences, -> { where("strength <= ?", 0.3) }
  scope :with_evidence, -> { where.not(evidence_refs: []) }
  scope :temporal, -> { where.not(temporal_extent: nil) }

  # Callbacks
  before_validation :calculate_strength
  before_validation :generate_repr_text
  after_commit :sync_to_graph, on: [:create, :update]
  after_commit :remove_from_graph, on: :destroy

  # Instance methods
  def impact_assessment
    return "unknown" if strength.nil?
    return "transformative" if strength > 0.8
    return "significant" if strength > 0.6
    return "moderate" if strength > 0.4
    return "minor" if strength > 0.2
    "negligible"
  end

  def has_evidence?
    evidence_refs.present? && evidence_refs.any?
  end

  def duration
    return nil unless temporal_extent.is_a?(Hash)
    
    start_time = temporal_extent["start"]
    end_time = temporal_extent["end"]
    
    return nil unless start_time && end_time
    
    Time.parse(end_time) - Time.parse(start_time)
  rescue StandardError
    nil
  end

  def propagation_paths
    # Trace how this emanation spreads through the graph
    paths = []
    
    # Direct influences
    influenced_ideas.each do |idea|
      paths << { type: "direct", target: idea, strength: strength }
    end
    
    # Indirect influences through relationships
    relationals.each do |rel|
      paths << { type: "relational", target: rel.target, via: rel, strength: strength * 0.7 }
    end
    
    paths
  end

  private

  def calculate_strength
    return if strength.present?
    
    # Auto-calculate strength based on evidence and connections
    evidence_score = evidence_refs&.size.to_f / 10.0
    connection_score = (ideas.size + experiences.size).to_f / 20.0
    
    self.strength = [evidence_score + connection_score, 1.0].min
  end

  def generate_repr_text
    type_label = influence_type&.humanize || "Unknown"
    impact_label = impact_assessment.capitalize
    
    self.repr_text = "#{type_label} influence (#{impact_label}): #{pathway.truncate(200)}"
  end

  def sync_to_graph
    Graph::EmanationWriter.new(self).sync
  rescue StandardError => e
    Rails.logger.error "Failed to sync Emanation #{id} to graph: #{e.message}"
  end

  def remove_from_graph
    Graph::EmanationRemover.new(self).remove
  rescue StandardError => e
    Rails.logger.error "Failed to remove Emanation #{id} from graph: #{e.message}"
  end
end
