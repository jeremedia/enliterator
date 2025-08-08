# frozen_string_literal: true

# == Schema Information
#
# Table name: experiences
#
#  id                       :bigint           not null, primary key
#  agent_label              :string
#  context                  :text
#  narrative_text           :text             not null
#  sentiment                :string
#  observed_at              :datetime         not null
#  repr_text                :text             not null
#  provenance_and_rights_id :bigint           not null
#  actor_id                 :bigint
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#
# Indexes
#
#  index_experiences_on_actor_id                  (actor_id)
#  index_experiences_on_agent_label               (agent_label)
#  index_experiences_on_narrative_trgm            (narrative_text) USING gin
#  index_experiences_on_observed_at               (observed_at)
#  index_experiences_on_provenance_and_rights_id  (provenance_and_rights_id)
#  index_experiences_on_sentiment                 (sentiment)
#
class Experience < ApplicationRecord
  include HasRights
  include TimeTrackable
  include PgSearch::Model
  
  # Full-text search
  pg_search_scope :search_by_content,
    against: [:agent_label, :narrative_text, :context, :repr_text],
    using: {
      tsearch: { prefix: true, dictionary: "english" },
      trigram: { threshold: 0.3 }
    }
  
  # Associations
  has_many :manifest_experiences
  has_many :manifests, through: :manifest_experiences
  
  has_many :experience_emanations
  has_many :emanations, through: :experience_emanations
  
  has_many :experience_practicals
  has_many :practicals, through: :experience_practicals
  
  # Optional actor association
  belongs_to :actor, optional: true
  
  # Validations
  validates :narrative_text, presence: true
  validates :observed_at, presence: true
  validates :repr_text, presence: true, length: { maximum: 500 }
  
  # Scopes
  scope :by_sentiment, ->(sentiment) { where(sentiment: sentiment) }
  scope :by_agent, ->(agent) { where(agent_label: agent) }
  scope :recent, -> { order(observed_at: :desc) }
  
  # Callbacks
  before_validation :generate_repr_text, if: :should_regenerate_repr_text?
  before_save :sanitize_narrative_text
  
  # Neo4j synchronization
  after_commit :sync_to_graph, on: [:create, :update]
  after_commit :remove_from_graph, on: :destroy
  
  def canonical_name
    "Experience ##{id}" # Experiences don't have natural names
  end
  
  def pool_type
    "experience"
  end
  
  # Graph relationships
  def elicited_by_manifests
    manifests.publishable
  end
  
  def inspires_emanations
    emanations.publishable
  end
  
  def validates_practicals
    practicals.joins(:experience_practicals)
             .where(experience_practicals: { relation_type: "validates" })
             .publishable
  end
  
  def validated_by_practicals
    practicals.joins(:experience_practicals)
             .where(experience_practicals: { relation_type: "validated_by" })
             .publishable
  end
  
  # Path generation helpers
  def to_path_node
    agent = agent_label.presence || "Anonymous"
    "Experience(#{agent}, #{observed_at.strftime('%Y-%m-%d')})"
  end
  
  def outgoing_relations
    relations = []
    
    emanations.each do |emanation|
      relations << {
        verb: "inspires",
        target: emanation,
        path: "#{to_path_node} → inspires → #{emanation.to_path_node}"
      }
    end
    
    validates_practicals.each do |practical|
      relations << {
        verb: "validates",
        target: practical,
        path: "#{to_path_node} → validates → #{practical.to_path_node}"
      }
    end
    
    relations
  end
  
  # Privacy and rights helpers
  def anonymized_text
    return narrative_text if publishable?
    
    # Return redacted version for non-publishable experiences
    "[Experience recorded on #{observed_at.strftime('%Y-%m-%d')}. " \
    "Content restricted due to privacy settings.]"
  end
  
  def excerpt(length: 200)
    return anonymized_text unless publishable?
    
    narrative_text.truncate(length)
  end
  
  private
  
  def generate_repr_text
    agent = agent_label.presence || "Anonymous"
    date = observed_at&.strftime("%Y-%m-%d") || "undated"
    sentiment_label = sentiment.present? ? " [#{sentiment}]" : ""
    
    # Create a short, rights-clean representation
    text_preview = if publishable?
                     narrative_text.truncate(100, separator: " ")
                   else
                     "Private experience"
                   end
    
    self.repr_text = "#{agent} - #{date}#{sentiment_label}: #{text_preview}"
  end
  
  def should_regenerate_repr_text?
    agent_label_changed? || narrative_text_changed? || 
    observed_at_changed? || sentiment_changed? || repr_text.blank?
  end
  
  def sanitize_narrative_text
    # Remove any potentially sensitive information if not publishable
    return if publishable?
    
    # This is a placeholder - implement actual sanitization logic
    # based on your privacy requirements
  end
  
  def sync_to_graph
    return unless defined?(Graph::ExperienceWriter)
    Graph::ExperienceWriter.new(self).sync
  rescue StandardError => e
    Rails.logger.error "Failed to sync Experience #{id} to graph: #{e.message}"
  end
  
  def remove_from_graph
    return unless defined?(Graph::ExperienceRemover)
    Graph::ExperienceRemover.new(self).remove
  rescue StandardError => e
    Rails.logger.error "Failed to remove Experience #{id} from graph: #{e.message}"
  end
end
