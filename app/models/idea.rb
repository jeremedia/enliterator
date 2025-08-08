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
# Captures the "why" - principles, theories, intents, design rationales
class Idea < ApplicationRecord
  include HasRights
  include TimeTrackable
  include PgSearch::Model
  
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
