# frozen_string_literal: true

# == Schema Information
#
# Table name: relationals
#
#  id                       :bigint           not null, primary key
#  relation_type            :string           not null
#  source_type              :string           not null
#  source_id                :bigint           not null
#  target_type              :string           not null
#  target_id                :bigint           not null
#  strength                 :float
#  period                   :jsonb
#  provenance_and_rights_id :bigint           not null
#  valid_time_start         :datetime         not null
#  valid_time_end           :datetime
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  repr_text                :text             not null
#
# Indexes
#
#  index_relationals_on_provenance_and_rights_id             (provenance_and_rights_id)
#  index_relationals_on_relation_type                        (relation_type)
#  index_relationals_on_source                               (source_type,source_id)
#  index_relationals_on_source_type_and_source_id            (source_type,source_id)
#  index_relationals_on_target                               (target_type,target_id)
#  index_relationals_on_target_type_and_target_id            (target_type,target_id)
#  index_relationals_on_valid_time_start_and_valid_time_end  (valid_time_start,valid_time_end)
#
class Relational < ApplicationRecord
  include EknPoolEntity

  # Enums - from spec Relation Verb Glossary (closed set) + Universal content support
  enum :relation_type, {
    # Forward relationships - Original spec
    embodies: "embodies",
    elicits: "elicits",
    influences: "influences",
    refines: "refines",
    version_of: "version_of",
    co_occurs_with: "co_occurs_with",
    located_at: "located_at",
    adjacent_to: "adjacent_to",
    validated_by: "validated_by",
    supports: "supports",
    refutes: "refutes",
    diffuses_through: "diffuses_through",
    # Reverse relationships - Original spec  
    is_embodiment_of: "is_embodiment_of",
    is_elicited_by: "is_elicited_by",
    is_influenced_by: "is_influenced_by",
    is_refined_by: "is_refined_by",
    has_version: "has_version",
    hosts: "hosts",
    validates: "validates",
    # Universal content support - Geopolitical/Research relations
    bilateral_cooperation: "bilateral_cooperation",
    bilateral_partnership: "bilateral_partnership", 
    partnership: "partnership",
    cooperation: "cooperation",
    interdependence: "interdependence",
    collaboration: "collaboration",
    alliance: "alliance",
    agreement: "agreement",
    treaty: "treaty",
    # Generic fallbacks
    relates_to: "relates_to",
    connected_to: "connected_to",
    associated_with: "associated_with"
  }, prefix: true

  # Model-driven extraction configuration
  extraction_config do
    canonical_name "Relational"
    description "Connections, lineages, and networks between entities - relationship discovery"
    
    field :relation_type, type: :enum,
      values: -> { relation_types.keys },  # Live from model enum - 31 values!
      default: 'relates_to',
      hints: "embodies: A contains/expresses B; elicits: A triggers B; influences: A affects B; refines: A improves B; supports: A backs B; refutes: A contradicts B; cooperation/partnership: collaborative relationships; adjacent_to/located_at: spatial relationships"
      
    field :source_type, type: :string, required: true,
      examples: ["Actor", "Spatial", "Evidence", "Risk", "Idea", "Manifest"],
      hints: "The entity type that is the source of this relationship (what relates FROM)"
      
    field :source_id, type: :integer, required: true,
      examples: [1, 15, 42, 127],
      hints: "The database ID of the source entity"
      
    field :target_type, type: :string, required: true,
      examples: ["Actor", "Spatial", "Evidence", "Risk", "Idea", "Manifest"],
      hints: "The entity type that is the target of this relationship (what relates TO)"
      
    field :target_id, type: :integer, required: true,
      examples: [1, 15, 42, 127],
      hints: "The database ID of the target entity"
      
    field :strength, type: :float, required: false,
      examples: [0.95, 0.87, 0.73, 0.42],
      hints: "Relationship confidence/strength score between 0.0 (weak) and 1.0 (strong)"
      
    field :period, type: :json, required: false,
      examples: [
        {"start": "2022-01-01", "end": "2023-12-31"},
        {"active_during": "Arctic research season 2023"}
      ],
      hints: "Time period when this relationship was active or observed"
  end

  # Polymorphic associations (EknPoolEntity provides provenance_and_rights)
  belongs_to :source, polymorphic: true
  belongs_to :target, polymorphic: true

  # Additional validations (EknPoolEntity provides common ones)
  validates :source, presence: true
  validates :target, presence: true
  validates :strength, numericality: { in: 0..1 }, allow_nil: true
  validate :no_self_reference
  validate :valid_relation_direction

  # Scopes
  scope :forward_relations, -> { where(relation_type: %w[embodies elicits influences refines version_of co_occurs_with located_at adjacent_to validated_by supports refutes diffuses_through bilateral_cooperation bilateral_partnership partnership cooperation interdependence collaboration alliance agreement treaty relates_to connected_to associated_with]) }
  scope :reverse_relations, -> { where(relation_type: %w[is_embodiment_of is_elicited_by is_influenced_by is_refined_by has_version hosts validates]) }
  scope :between, ->(source, target) { where(source: source, target: target) }
  scope :involving, ->(entity) { where(source: entity).or(where(target: entity)) }

  # Callbacks (EknPoolEntity provides sync_to_graph)
  before_validation :generate_repr_text

  private

  def no_self_reference
    return unless source_type == target_type && source_id == target_id

    errors.add(:target, "cannot be the same as source")
  end

  def valid_relation_direction
    # Ensure relation type matches the intended direction
    return unless source && target

    # Add specific validation logic based on relation type and entity types
  end

  def generate_repr_text
    return unless source && target && relation_type

    self.repr_text = "#{source.class.name}(#{source.try(:label) || source.id}) " \
                     "→ #{relation_type.humanize.downcase} → " \
                     "#{target.class.name}(#{target.try(:label) || target.id})"
  end
end
