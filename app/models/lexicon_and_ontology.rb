# frozen_string_literal: true

# Lexicon and Ontology pool: canonical terms, definitions, and relationships
class LexiconAndOntology < ApplicationRecord
  include HasRights
  include TimeTrackable

  # Validations
  validates :term, presence: true, uniqueness: { scope: :valid_time_end }
  validates :definition, presence: true
  validates :pool_association, presence: true
  validates :repr_text, presence: true, length: { maximum: 500 }
  validate :surface_forms_valid
  validate :relations_valid

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
    
    # Try surface forms
    where("? = ANY(surface_forms)", input).first ||
      where("LOWER(?) = ANY(LOWER(surface_forms::text)::text[])", input.downcase).first
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
    Graph::LexiconWriter.new(self).sync
  rescue StandardError => e
    Rails.logger.error "Failed to sync LexiconAndOntology #{id} to graph: #{e.message}"
  end

  def remove_from_graph
    Graph::LexiconRemover.new(self).remove
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