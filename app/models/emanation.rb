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
  include HasRights
  include TimeTrackable

  # Enums
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
