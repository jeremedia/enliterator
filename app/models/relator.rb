# frozen_string_literal: true

# Relator Pool - Relationships, connections, dependencies, associations
# Part of the Ten Pool Canon for representing explicit connections
class Relator < ApplicationRecord
  # Relationships  
  belongs_to :provenance_and_rights
  
  # Validations
  validates :label, presence: true
  validates :relation_type, presence: true
  validates :repr_text, presence: true
  validates :valid_time_start, presence: true
  
  # Callbacks for Neo4j synchronization (maps to Relational pool)
  after_commit :sync_to_graph, on: [:create, :update]
  after_commit :remove_from_graph, on: :destroy
  
  # Enums for relation types
  enum :relation_type, {
    correlation: 'correlation',        # Statistical correlations
    causation: 'causation',           # Cause-effect relationships  
    dependency: 'dependency',         # Dependencies between entities
    association: 'association',       # General associations
    linkage: 'linkage',              # Direct connections (renamed from connection)
    influence: 'influence',           # Influence relationships
    partnership: 'partnership',       # Collaborative relationships
    hierarchy: 'hierarchy'           # Hierarchical relationships
  }
  
  # Scopes
  scope :by_relation_type, ->(type) { where(relation_type: type) }
  scope :strong_relations, -> { where('strength > ?', 0.7) }
  scope :causal, -> { where(relation_type: 'causation') }
  
  # Instance methods
  def relationship_description
    "#{source_label} #{relation_type.humanize.downcase} #{target_label}"
  end
  
  def strength_category
    return 'weak' if strength < 0.4
    return 'moderate' if strength < 0.7
    'strong'
  end
  
  def bidirectional?
    bidirectional || false
  end
  
  # Class methods  
  def self.search_relationships(query)
    where('label ILIKE ? OR source_label ILIKE ? OR target_label ILIKE ?',
          "%#{query}%", "%#{query}%", "%#{query}%")
  end
  
  def self.between_entities(source, target)
    where(source_label: source, target_label: target)
    .or(where(source_label: target, target_label: source, bidirectional: true))
  end
  
  private
  
  def sync_to_graph
    return unless defined?(Graph::RelatorWriter)
    Graph::RelatorWriter.new(self).sync
  rescue StandardError => e
    Rails.logger.error "Failed to sync Relator #{id} to graph: #{e.message}"
  end
  
  def remove_from_graph
    return unless defined?(Graph::RelatorRemover)
    Graph::RelatorRemover.new(self).remove
  rescue StandardError => e
    Rails.logger.error "Failed to remove Relator #{id} from graph: #{e.message}"
  end
end