# frozen_string_literal: true

# Captures the "what" - concrete instances and artifacts
class Manifest < ApplicationRecord
  include HasRights
  include TimeTrackable
  include PgSearch::Model
  
  # Full-text search
  pg_search_scope :search_by_content,
    against: [:label, :manifest_type, :repr_text],
    using: {
      tsearch: { prefix: true, dictionary: "english" },
      trigram: { threshold: 0.3 }
    }
  
  # Associations
  has_many :idea_manifests
  has_many :ideas, through: :idea_manifests
  
  has_many :manifest_experiences
  has_many :experiences, through: :manifest_experiences
  
  has_many :evolutionary_versions,
           class_name: "Evolutionary",
           foreign_key: :manifest_version_id
  
  has_many :relationals, as: :source
  has_many :relationals_as_target, class_name: "Relational", as: :target
  
  # Validations
  validates :label, presence: true
  validates :repr_text, presence: true, length: { maximum: 500 }
  validates :valid_time_start, presence: true
  
  # Scopes
  scope :by_type, ->(type) { where(manifest_type: type) }
  scope :with_spatial_ref, -> { where.not(spatial_ref: nil) }
  scope :with_components, -> { where("jsonb_array_length(components) > 0") }
  
  # Callbacks
  before_validation :generate_repr_text, if: :should_regenerate_repr_text?
  
  # Neo4j synchronization
  after_commit :sync_to_graph, on: [:create, :update]
  after_commit :remove_from_graph, on: :destroy
  
  def canonical_name
    label
  end
  
  def pool_type
    "manifest"
  end
  
  # Graph relationships
  def embodied_by_ideas
    ideas.publishable
  end
  
  def elicits_experiences
    experiences.publishable
  end
  
  def co_occurs_with
    Relational.where(source: self, relation_type: "co_occurs_with")
              .or(Relational.where(target: self, relation_type: "co_occurs_with"))
  end
  
  def versions
    evolutionary_versions.publishable
  end
  
  # Path generation helpers
  def to_path_node
    "Manifest(#{canonical_name})"
  end
  
  def outgoing_relations
    relations = []
    
    experiences.each do |experience|
      relations << {
        verb: "elicits",
        target: experience,
        path: "#{to_path_node} → elicits → #{experience.to_path_node}"
      }
    end
    
    co_occurs_with.each do |relational|
      other = relational.source == self ? relational.target : relational.source
      relations << {
        verb: "co_occurs_with",
        target: other,
        path: "#{to_path_node} ↔ co_occurs_with ↔ #{other.to_path_node}"
      }
    end
    
    relations
  end
  
  # Temporal helpers
  def active_during?(start_time, end_time)
    return false unless time_bounds.present?
    
    bounds_start = Time.parse(time_bounds["start"]) rescue nil
    bounds_end = Time.parse(time_bounds["end"]) rescue nil
    
    return false unless bounds_start
    
    bounds_start <= end_time && (bounds_end.nil? || bounds_end > start_time)
  end
  
  private
  
  def generate_repr_text
    type_label = manifest_type.presence || "artifact"
    year = valid_time_start&.year || "undated"
    location = spatial_ref.present? ? " @#{spatial_ref}" : ""
    
    self.repr_text = "#{label} (#{type_label}, #{year}#{location})"
  end
  
  def should_regenerate_repr_text?
    label_changed? || manifest_type_changed? || spatial_ref_changed? || 
    valid_time_start_changed? || repr_text.blank?
  end
  
  def sync_to_graph
    return unless defined?(Graph::ManifestWriter)
    Graph::ManifestWriter.new(self).sync
  rescue StandardError => e
    Rails.logger.error "Failed to sync Manifest #{id} to graph: #{e.message}"
  end
  
  def remove_from_graph
    return unless defined?(Graph::ManifestRemover)
    Graph::ManifestRemover.new(self).remove
  rescue StandardError => e
    Rails.logger.error "Failed to remove Manifest #{id} from graph: #{e.message}"
  end
end