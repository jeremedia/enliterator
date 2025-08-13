# frozen_string_literal: true

# == Schema Information
#
# Table name: manifests
#
#  id                       :bigint           not null, primary key
#  label                    :string           not null
#  manifest_type            :string
#  components               :jsonb
#  time_bounds              :jsonb
#  spatial_ref              :string
#  repr_text                :text             not null
#  provenance_and_rights_id :bigint           not null
#  valid_time_start         :datetime         not null
#  valid_time_end           :datetime
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#
# Indexes
#
#  index_manifests_on_components                           (components) USING gin
#  index_manifests_on_label                                (label)
#  index_manifests_on_label_trgm                           (label) USING gin
#  index_manifests_on_manifest_type                        (manifest_type)
#  index_manifests_on_provenance_and_rights_id             (provenance_and_rights_id)
#  index_manifests_on_spatial_ref                          (spatial_ref)
#  index_manifests_on_valid_time_start_and_valid_time_end  (valid_time_start,valid_time_end)
#
class Manifest < ApplicationRecord
  include EknPoolEntity
  include PgSearch::Model
  
  # Enums for artifact classification
  enum :manifest_type, {
    document: "document",       # Papers, reports, specifications
    software: "software",       # Applications, scripts, code
    hardware: "hardware",       # Physical devices, instruments
    structure: "structure",     # Buildings, installations
    process: "process",         # Workflows, procedures
    protocol: "protocol",       # Standards, guidelines  
    dataset: "dataset",         # Data collections, databases
    model: "model",            # Conceptual or physical models
    framework: "framework",     # Systematic approaches
    system: "system"           # Integrated complex systems
  }, prefix: true

  enum :artifact_category, {
    research: 0,        # Scientific/academic artifacts
    operational: 1,     # Day-to-day operations
    administrative: 2,  # Governance, management
    educational: 3,     # Teaching, training materials
    cultural: 4,        # Traditions, practices, art
    technical: 5,       # Engineering, technical specs
    policy: 6,          # Rules, regulations, guidelines
    personal: 7         # Individual contributions, stories
  }, prefix: true

  enum :completion_status, {
    concept: 0,         # Initial idea, planning stage
    draft: 1,           # Work in progress, incomplete
    prototype: 2,       # Working model, testing phase
    beta: 3,            # Feature complete, refinement
    released: 4,        # Publicly available, stable
    mature: 5,          # Well-established, proven
    deprecated: 6,      # Still exists but discouraged
    archived: 7         # Historical, no longer active
  }, prefix: true

  enum :accessibility_level, {
    public: 0,          # Openly accessible to everyone
    restricted: 1,      # Limited access, some barriers
    internal: 2,        # Organization/community only
    confidential: 3,    # Sensitive, need-to-know
    classified: 4       # Highly restricted, secure
  }, prefix: true

  enum :format_type, {
    physical: 0,        # Tangible, material artifacts
    digital: 1,         # Electronic, software-based
    hybrid: 2,          # Combination of physical/digital
    virtual: 3,         # Exists in virtual/online space
    conceptual: 4       # Abstract, idea-based
  }, prefix: true

  # Model-driven extraction configuration
  extraction_config do
    canonical_name "Manifest"
    description "Concrete artifacts, implementations, instances - tangible outcomes and deliverables"
    
    field :label, type: :string, required: true,
      examples: [
        "Arctic Research Database 2023",
        "Community Resilience Protocol",
        "Sea Ice Monitoring System",
        "Climate Adaptation Framework",
        "Research Station Blueprint"
      ],
      hints: "The name or title of the concrete artifact, implementation, or manifestation"
      
    field :manifest_type, type: :enum,
      values: -> { manifest_types.keys },  # Live from model enum - 10 values!
      default: 'document',
      hints: "document: papers/reports; software: applications/code; hardware: devices; structure: buildings; process: workflows; protocol: standards; dataset: data collections; model: conceptual/physical models; framework: systematic approaches; system: integrated complexes"
      
    field :artifact_category, type: :enum,
      values: -> { artifact_categories.keys },  # Live from model enum - 8 values!
      default: 'research',
      hints: "research: scientific/academic; operational: day-to-day; administrative: governance; educational: teaching; cultural: traditions/art; technical: engineering; policy: rules/regulations; personal: individual contributions"
      
    field :completion_status, type: :enum,
      values: -> { completion_statuses.keys },  # Live from model enum - 8 values!
      default: 'released',
      hints: "concept: planning stage; draft: work in progress; prototype: testing phase; beta: feature complete; released: publicly available; mature: well-established; deprecated: discouraged use; archived: historical only"
      
    field :accessibility_level, type: :enum,
      values: -> { accessibility_levels.keys },  # Live from model enum - 5 values!
      default: 'public',
      hints: "public: openly accessible; restricted: limited access; internal: organization only; confidential: need-to-know; classified: highly restricted"
      
    field :format_type, type: :enum,
      values: -> { format_types.keys },  # Live from model enum - 5 values!
      default: 'digital',
      hints: "physical: tangible/material; digital: electronic/software; hybrid: physical+digital; virtual: online/virtual space; conceptual: abstract/idea-based"
      
    field :spatial_ref, type: :string, required: false,
      examples: ["Arctic Research Station, Svalbard", "University of Alaska Fairbanks", "Remote sensor location 70.2°N 150.4°W"],
      hints: "Geographic location, institution, or spatial reference where this artifact exists or was created"
      
    field :components, type: :json, required: false,
      examples: [
        ["Data collection module", "Analysis engine", "Visualization interface"],
        ["Hardware sensors", "Communication system", "Power management"],
        ["Research protocols", "Quality assurance procedures", "Reporting templates"]
      ],
      hints: "Array of components, parts, or elements that make up this artifact"
      
    field :time_bounds, type: :json, required: false,
      examples: [
        {"start": "2023-01-01", "end": "2023-12-31", "active_during": "Arctic research season"},
        {"deployment": "2022-06-15", "operational_until": "2025-06-15"}
      ],
      hints: "Temporal information about when this artifact was created, deployed, or is/was active"
  end
  
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
