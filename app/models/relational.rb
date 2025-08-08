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
  include HasRights
  include TimeTrackable

  # Enums - from spec Relation Verb Glossary (closed set)
  enum :relation_type, {
    # Forward relationships
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
    # Reverse relationships
    is_embodiment_of: "is_embodiment_of",
    is_elicited_by: "is_elicited_by",
    is_influenced_by: "is_influenced_by",
    is_refined_by: "is_refined_by",
    has_version: "has_version",
    hosts: "hosts",
    validates: "validates"
  }, prefix: true

  # Polymorphic associations
  belongs_to :source, polymorphic: true
  belongs_to :target, polymorphic: true

  # Validations
  validates :relation_type, presence: true
  validates :repr_text, presence: true, length: { maximum: 500 }
  validates :source, presence: true
  validates :target, presence: true
  validate :no_self_reference
  validate :valid_relation_direction

  # Scopes
  scope :forward_relations, -> { where(relation_type: %w[embodies elicits influences refines version_of co_occurs_with located_at adjacent_to validated_by supports refutes diffuses_through]) }
  scope :reverse_relations, -> { where(relation_type: %w[is_embodiment_of is_elicited_by is_influenced_by is_refined_by has_version hosts validates]) }
  scope :between, ->(source, target) { where(source: source, target: target) }
  scope :involving, ->(entity) { where(source: entity).or(where(target: entity)) }

  # Callbacks
  before_validation :generate_repr_text
  after_commit :sync_to_graph, on: [:create, :update]
  after_commit :remove_from_graph, on: :destroy

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

  def sync_to_graph
    Graph::RelationalWriter.new(self).sync
  rescue StandardError => e
    Rails.logger.error "Failed to sync Relational #{id} to graph: #{e.message}"
  end

  def remove_from_graph
    Graph::RelationalRemover.new(self).remove
  rescue StandardError => e
    Rails.logger.error "Failed to remove Relational #{id} from graph: #{e.message}"
  end
end
