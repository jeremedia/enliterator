# frozen_string_literal: true

# == Schema Information
#
# Table name: ideas
#
#  id                       :bigint           not null, primary key
#  label                    :string           not null
#  abstract                 :text             not null
#  principle_tags           :jsonb
#  authorship               :string
#  inception_date           :date             not null
#  repr_text                :text             not null
#  is_canonical             :boolean          default(FALSE), not null
#  provenance_and_rights_id :bigint           not null
#  valid_time_start         :datetime         not null
#  valid_time_end           :datetime
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#
# Indexes
#
#  index_ideas_on_abstract_trgm                        (abstract) USING gin
#  index_ideas_on_is_canonical                         (is_canonical)
#  index_ideas_on_label                                (label)
#  index_ideas_on_label_trgm                           (label) USING gin
#  index_ideas_on_principle_tags                       (principle_tags) USING gin
#  index_ideas_on_provenance_and_rights_id             (provenance_and_rights_id)
#  index_ideas_on_valid_time_start_and_valid_time_end  (valid_time_start,valid_time_end)
#
class Idea < ApplicationRecord
  include EknPoolEntity
  include PgSearch::Model
  
  # Enums for idea classification
  enum :idea_type, {
    theory: 0,           # Scientific theory or systematic explanation
    principle: 1,        # Fundamental rule or guideline
    concept: 2,          # Abstract notion or general idea
    hypothesis: 3,       # Proposed explanation or prediction
    framework: 4,        # Structured approach or methodology
    paradigm: 5,         # Fundamental model or worldview
    philosophy: 6,       # Fundamental beliefs or approach
    methodology: 7,      # Systematic procedure or approach
    heuristic: 8,        # Rule of thumb or mental shortcut
    axiom: 9            # Self-evident truth or principle
  }, prefix: true

  enum :maturity_level, {
    emerging: 0,         # New, experimental, unproven
    developing: 1,       # Growing evidence, gaining acceptance
    established: 2,      # Well-supported, widely accepted
    foundational: 3,     # Core to field, fundamental
    canonical: 4,        # Standard reference, authoritative
    contested: 5,        # Disputed, controversial
    deprecated: 6        # Outdated, superseded
  }, prefix: true

  enum :scope, {
    local: 0,           # Limited to specific location/context
    regional: 1,        # Applicable to broader region
    national: 2,        # Country or nation-wide relevance
    global: 3,          # Worldwide applicability
    universal: 4,       # Applies everywhere, fundamental
    domain_specific: 5, # Limited to specific field/discipline
    interdisciplinary: 6 # Spans multiple fields/disciplines
  }, prefix: true

  # Model-driven extraction configuration
  extraction_config do
    canonical_name "Idea"
    description "Principles, theories, concepts, abstract knowledge - intellectual and conceptual entities"
    
    field :label, type: :string, required: true,
      examples: [
        "Radical inclusion",
        "Climate change adaptation",
        "Participatory governance",
        "Sustainable development",
        "Resilience theory"
      ],
      hints: "The name or title of the idea, concept, or principle"
      
    field :abstract, type: :text, required: true,
      examples: [
        "The principle that all people should be welcomed and included regardless of background",
        "Strategies for adjusting systems and practices to address climate change impacts",
        "Democratic decision-making that involves citizens in governance processes"
      ],
      hints: "Comprehensive description of the idea, its meaning, and implications"
      
    field :idea_type, type: :enum,
      values: -> { idea_types.keys },  # Live from model enum - 10 values!
      default: 'concept',
      hints: "theory: systematic explanation; principle: fundamental rule; concept: abstract notion; hypothesis: proposed explanation; framework: structured approach; paradigm: worldview; methodology: procedure; heuristic: rule of thumb"
      
    field :maturity_level, type: :enum,
      values: -> { maturity_levels.keys },  # Live from model enum - 7 values!
      default: 'developing',
      hints: "emerging: new/experimental; developing: gaining acceptance; established: well-supported; foundational: core to field; canonical: authoritative; contested: disputed; deprecated: outdated"
      
    field :scope, type: :enum,
      values: -> { scopes.keys },  # Live from model enum - 7 values!
      default: 'domain_specific',
      hints: "local: specific context; regional: broader area; national: country-wide; global: worldwide; universal: fundamental; domain_specific: single field; interdisciplinary: multiple fields"
      
    field :authorship, type: :string, required: false,
      examples: ["Dr. Sarah Johnson", "Arctic Research Collective", "IPCC Working Group", "Anonymous"],
      hints: "Who developed, authored, or is credited with this idea"
      
    field :principle_tags, type: :json, required: false,
      examples: [
        ["sustainability", "environmental"],
        ["democracy", "participation", "governance"],
        ["resilience", "adaptation", "systems"]
      ],
      hints: "Array of tags or keywords that classify the principle or idea"
  end
  
  # Full-text search
  pg_search_scope :search_by_content,
    against: [:label, :abstract, :repr_text],
    using: {
      tsearch: { prefix: true, dictionary: "english" },
      trigram: { threshold: 0.3 }
    }
  
  # Associations
  has_many :idea_manifests
  has_many :manifests, through: :idea_manifests
  
  has_many :idea_practicals
  has_many :practicals, through: :idea_practicals
  
  has_many :idea_emanations
  has_many :emanations, through: :idea_emanations
  
  has_many :evolutionary_refinements, 
           class_name: "Evolutionary", 
           foreign_key: :refined_idea_id
  
  # Validations
  validates :label, presence: true
  validates :abstract, presence: true
  validates :repr_text, presence: true, length: { maximum: 500 }
  validates :inception_date, presence: true
  
  # Scopes
  scope :by_principle_tag, ->(tag) { where("? = ANY(principle_tags)", tag) }
  scope :with_authorship, ->(author) { where(authorship: author) }
  scope :canonical, -> { where(is_canonical: true) }
  
  # Callbacks
  before_validation :generate_repr_text, if: :should_regenerate_repr_text?
  
  # Neo4j synchronization
  after_commit :sync_to_graph, on: [:create, :update]
  after_commit :remove_from_graph, on: :destroy
  
  def canonical_name
    label
  end
  
  def pool_type
    "idea"
  end
  
  # Graph relationships
  def embodies_manifests
    manifests.publishable
  end
  
  def codifies_practicals
    practicals.publishable
  end
  
  def influences_emanations
    emanations.publishable
  end
  
  def refined_by_evolutions
    evolutionary_refinements.publishable
  end
  
  # Path generation helpers
  def to_path_node
    "Idea(#{canonical_name})"
  end
  
  def outgoing_relations
    relations = []
    
    manifests.each do |manifest|
      relations << {
        verb: "embodies",
        target: manifest,
        path: "#{to_path_node} → embodies → #{manifest.to_path_node}"
      }
    end
    
    practicals.each do |practical|
      relations << {
        verb: "codifies",
        target: practical,
        path: "#{to_path_node} → codifies → #{practical.to_path_node}"
      }
    end
    
    emanations.each do |emanation|
      relations << {
        verb: "influences",
        target: emanation,
        path: "#{to_path_node} → influences → #{emanation.to_path_node}"
      }
    end
    
    relations
  end
  
  private
  
  def generate_repr_text
    # Generate short, rights-clean, canonical representation
    principle = principle_tags&.first || "principle"
    year = inception_date&.year || "undated"
    
    self.repr_text = "#{label} (#{principle}, #{year})"
  end
  
  def should_regenerate_repr_text?
    label_changed? || principle_tags_changed? || inception_date_changed? || repr_text.blank?
  end
  
  def sync_to_graph
    return unless defined?(Graph::IdeaWriter)
    Graph::IdeaWriter.new(self).sync
  rescue StandardError => e
    Rails.logger.error "Failed to sync Idea #{id} to graph: #{e.message}"
  end
  
  def remove_from_graph
    return unless defined?(Graph::IdeaRemover)
    Graph::IdeaRemover.new(self).remove
  rescue StandardError => e
    Rails.logger.error "Failed to remove Idea #{id} from graph: #{e.message}"
  end
end
