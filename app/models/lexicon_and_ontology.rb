# frozen_string_literal: true

# == Schema Information
#
# Table name: lexicon_and_ontologies
#
#  id                       :bigint           not null, primary key
#  term                     :string           not null
#  definition               :text
#  canonical_description    :text
#  surface_forms            :jsonb
#  negative_surface_forms   :jsonb
#  type_mapping             :jsonb
#  unit_system              :string
#  schema_version           :string
#  provenance_and_rights_id :bigint           not null
#  valid_time_start         :datetime         not null
#  valid_time_end           :datetime
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  repr_text                :text             not null
#  pool_association         :string           not null
#  is_canonical             :boolean          default(FALSE), not null
#  relations                :jsonb
#
# Indexes
#
#  idx_on_valid_time_start_valid_time_end_5b95b14d20         (valid_time_start,valid_time_end)
#  index_lexicon_and_ontologies_on_negative_surface_forms    (negative_surface_forms) USING gin
#  index_lexicon_and_ontologies_on_provenance_and_rights_id  (provenance_and_rights_id)
#  index_lexicon_and_ontologies_on_surface_forms             (surface_forms) USING gin
#  index_lexicon_and_ontologies_on_term                      (term) UNIQUE
#
class LexiconAndOntology < ApplicationRecord
  include EknPoolEntity

  # Enums for term classification
  enum :term_type, {
    canonical: 0,        # Primary/preferred term
    synonym: 1,          # Alternative term  
    acronym: 2,          # Abbreviation
    technical: 3,        # Domain-specific term
    colloquial: 4,       # Common usage term
    negative: 5,         # Term to avoid/exclude
    deprecated: 6        # Previously used, now outdated
  }, prefix: true

  # Pool associations from Ten Pool Canon
  enum :pool_association_type, {
    idea: 'Idea',
    manifest: 'Manifest', 
    experience: 'Experience',
    relational: 'Relational',
    evolutionary: 'Evolutionary',
    practical: 'Practical',
    emanation: 'Emanation',
    provenance_and_rights: 'ProvenanceAndRights',
    lexicon_and_ontology: 'LexiconAndOntology',
    intent_and_task: 'IntentAndTask',
    actor_and_role: 'ActorAndRole',
    spatial: 'Spatial',
    evidence_and_observation: 'EvidenceAndObservation',
    risk_and_governance: 'RiskAndGovernance',
    method_and_model: 'MethodAndModel'
  }, prefix: true

  # Model-driven extraction configuration
  extraction_config do
    canonical_name "LexiconAndOntology"
    description "Definitions, canonical terms, vocabulary systems - knowledge representation and terminology management"
    
    field :term, type: :string, required: true,
      examples: [
        "Arctic research",
        "Sea ice extent", 
        "Climate change mitigation",
        "Data provenance",
        "Spatial analysis"
      ],
      hints: "The primary term or phrase being defined in the vocabulary"
      
    field :definition, type: :text, required: true,
      examples: [
        "Scientific investigation conducted in Arctic regions to understand climate patterns",
        "The area covered by sea ice in polar regions, measured by satellite observation",
        "Actions taken to reduce or prevent greenhouse gas emissions"
      ],
      hints: "Clear, comprehensive definition of the term for disambiguation and understanding"
      
    field :term_type, type: :enum,
      values: -> { term_types.keys },  # Live from model enum - 7 values!
      default: 'canonical',
      hints: "canonical: primary term; synonym: alternative; technical: domain-specific; colloquial: common usage; acronym: abbreviation; negative: avoid; deprecated: outdated"
      
    field :pool_association_type, type: :enum,
      values: -> { pool_association_types.keys },  # Live from model enum - 15 values!
      default: 'lexicon_and_ontology',
      hints: "Which pool in the Ten Pool Canon this term primarily relates to - helps with extraction routing and semantic classification"
      
    field :surface_forms, type: :json, required: false,
      examples: [
        ["Arctic research", "polar research", "northern research"],
        ["sea ice", "frozen seawater", "marine ice"],
        ["climate mitigation", "emission reduction", "carbon reduction"]
      ],
      hints: "Array of alternative ways this term appears in text - synonyms, variations, common phrasings"
      
    field :canonical_description, type: :text, required: false,
      examples: [
        "Standardized definition used across all Arctic research documentation",
        "Technical term as defined by IPCC climate reports",
        "Canonical form established by research community consensus"
      ],
      hints: "Expanded description explaining why this definition is canonical and how it should be used"
  end

  # Validations
  validates :term, presence: true, uniqueness: { scope: :valid_time_end }
  validates :definition, presence: true
  validates :pool_association, presence: true
  validates :repr_text, presence: true, length: { maximum: 500 }
  validate :surface_forms_valid
  validate :relations_valid

  # Callbacks
  before_validation do
    # Ensure canonical_description is always set (Neo4j requires it)
    self.canonical_description ||= definition
  end

  # Scopes
  scope :canonical, -> { where(is_canonical: true) }
  scope :by_pool, ->(pool) { where(pool_association: pool) }
  scope :with_surface_forms, -> { where.not(surface_forms: []) }
  scope :ambiguous, -> { where("jsonb_array_length(surface_forms) > 3") }
  scope :search_by_term, ->(query) { where("term ILIKE ?", "%#{query}%") }

  # Full-text search
  include PgSearch::Model
  pg_search_scope :search_surface_forms,
                  against: :term,
                  using: {
                    tsearch: { prefix: true },
                    trigram: { threshold: 0.3 }
                  }

  # Associations
  attr_accessor :ingest_batch # Transient attribute for batch context
  
  # Callbacks
  before_validation :normalize_arrays
  before_validation :generate_repr_text
  after_commit :sync_to_graph, on: [:create, :update]
  after_commit :remove_from_graph, on: :destroy
  after_commit :update_normalization_cache

  # Class methods
  def self.normalize_term(input)
    return nil if input.blank?
    
    # Try exact match first
    exact = find_by(term: input)
    return exact if exact
    
    # Try surface forms (JSONB array)
    where("surface_forms @> ?", [input].to_json).first ||
      where("EXISTS (SELECT 1 FROM jsonb_array_elements_text(surface_forms) elem WHERE LOWER(elem) = LOWER(?))", input).first
  end

  def self.find_canonical(input)
    term = normalize_term(input)
    return nil unless term
    
    term.canonical_term || term
  end

  # Instance methods
  def canonical_term
    return self if is_canonical
    
    # Find canonical term through relations
    canonical_id = relations&.dig("canonical_id")
    return nil unless canonical_id
    
    self.class.find_by(id: canonical_id, is_canonical: true)
  end

  def related_terms
    return [] unless relations.present?
    
    related_ids = [
      relations["broader_terms"],
      relations["narrower_terms"],
      relations["related_terms"]
    ].flatten.compact.uniq
    
    self.class.where(id: related_ids)
  end

  def hierarchical_path
    path = [self]
    current = self
    
    while current.relations&.dig("broader_terms")&.any?
      parent_id = current.relations["broader_terms"].first
      parent = self.class.find_by(id: parent_id)
      break unless parent
      
      path.unshift(parent)
      current = parent
    end
    
    path
  end

  def disambiguation_context
    {
      pool: pool_association,
      canonical: canonical_term&.term,
      surface_forms: surface_forms,
      negative_forms: negative_surface_forms,
      definition: definition
    }
  end

  private

  def normalize_arrays
    self.surface_forms = [] if surface_forms.nil?
    self.negative_surface_forms = [] if negative_surface_forms.nil?
    self.relations = {} if relations.nil?
  end

  def surface_forms_valid
    return if surface_forms.blank? && negative_surface_forms.blank?
    
    all_forms = (surface_forms + negative_surface_forms).compact
    
    # Check for duplicates
    if all_forms.size != all_forms.uniq.size
      errors.add(:surface_forms, "contains duplicates across positive and negative forms")
    end
    
    # Ensure all forms are strings
    unless all_forms.all? { |form| form.is_a?(String) }
      errors.add(:surface_forms, "must all be strings")
    end
  end

  def relations_valid
    return if relations.blank?
    
    allowed_keys = %w[canonical_id broader_terms narrower_terms related_terms see_also]
    invalid_keys = relations.keys - allowed_keys
    
    if invalid_keys.any?
      errors.add(:relations, "contains invalid keys: #{invalid_keys.join(', ')}")
    end
  end

  def generate_repr_text
    canonical_marker = is_canonical ? " [canonical]" : ""
    forms_count = surface_forms.size
    forms_summary = forms_count > 0 ? " (#{forms_count} forms)" : ""
    
    self.repr_text = "#{pool_association}/#{term}#{canonical_marker}#{forms_summary}: " \
                     "#{definition.truncate(200)}"
  end

  def sync_to_graph
    Graph::LexiconWriter.new(self, ingest_batch).sync
  rescue StandardError => e
    Rails.logger.error "Failed to sync LexiconAndOntology #{id} to graph: #{e.message}"
  end

  def remove_from_graph
    Graph::LexiconRemover.new(self, ingest_batch).remove
  rescue StandardError => e
    Rails.logger.error "Failed to remove LexiconAndOntology #{id} from graph: #{e.message}"
  end

  def update_normalization_cache
    Rails.cache.delete("lexicon:normalize:#{term}")
    surface_forms.each do |form|
      Rails.cache.delete("lexicon:normalize:#{form}")
    end
  end
end
