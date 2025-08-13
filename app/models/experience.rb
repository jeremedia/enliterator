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
  include EknPoolEntity
  include PgSearch::Model
  
  # Enums for experience classification (privacy-aware)
  enum :experience_type, {
    observation: 0,     # Witnessed events, phenomena
    participation: 1,   # Active involvement in activities
    reflection: 2,      # Personal thoughts, insights
    interview: 3,       # Structured conversation record
    testimony: 4,       # Formal account, evidence
    narrative: 5,       # Story-form personal account
    incident: 6,        # Specific event occurrence
    achievement: 7      # Accomplishments, milestones
  }, prefix: true

  enum :sentiment, {
    very_positive: 0,   # Highly favorable, joyful
    positive: 1,        # Generally favorable, pleasant
    neutral: 2,         # Balanced, factual, objective
    negative: 3,        # Generally unfavorable, difficult
    very_negative: 4,   # Highly unfavorable, distressing
    mixed: 5,           # Both positive and negative elements
    complex: 6          # Nuanced, hard to categorize
  }, prefix: true

  enum :reliability_level, {
    high: 0,           # Multiple sources, verified details
    medium: 1,         # Single source, plausible account
    low: 2,            # Uncertain details, gaps in account
    unverified: 3,     # Cannot confirm accuracy
    disputed: 4        # Conflicting accounts exist
  }, prefix: true

  enum :privacy_level, {
    public: 0,         # Openly shareable, no restrictions
    restricted: 1,     # Limited sharing, some sensitivity
    sensitive: 2,      # Personal but not confidential
    confidential: 3,   # Highly personal, consent required
    anonymous_only: 4  # Only with complete anonymization
  }, prefix: true

  enum :emotional_intensity, {
    minimal: 0,        # Factual, little emotional content
    low: 1,            # Some emotional elements
    moderate: 2,       # Clear emotional component
    high: 3,           # Strong emotional content
    intense: 4         # Overwhelming emotional content
  }, prefix: true

  # Model-driven extraction configuration (PRIVACY-FIRST)
  extraction_config do
    canonical_name "Experience"
    description "Lived outcomes, perceptions, subjective accounts - human experience and perspective capture (PRIVACY-AWARE)"
    
    field :experience_type, type: :enum,
      values: -> { experience_types.keys },  # Live from model enum - 8 values!
      default: 'observation',
      hints: "observation: witnessed events; participation: active involvement; reflection: personal insights; interview: structured record; testimony: formal account; narrative: story account; incident: specific event; achievement: accomplishments"
      
    field :sentiment, type: :enum,
      values: -> { sentiments.keys },  # Live from model enum - 7 values!
      default: 'neutral',
      hints: "very_positive: highly favorable; positive: generally favorable; neutral: balanced/objective; negative: generally unfavorable; very_negative: highly unfavorable; mixed: both positive/negative; complex: nuanced/hard to categorize"
      
    field :reliability_level, type: :enum,
      values: -> { reliability_levels.keys },  # Live from model enum - 5 values!
      default: 'medium',
      hints: "high: verified multiple sources; medium: single source, plausible; low: uncertain details; unverified: cannot confirm; disputed: conflicting accounts"
      
    field :privacy_level, type: :enum,
      values: -> { privacy_levels.keys },  # Live from model enum - 5 values!
      default: 'sensitive',
      hints: "public: openly shareable; restricted: limited sharing; sensitive: personal but not confidential; confidential: highly personal, consent required; anonymous_only: complete anonymization required"
      
    field :emotional_intensity, type: :enum,
      values: -> { emotional_intensities.keys },  # Live from model enum - 5 values!
      default: 'moderate',
      hints: "minimal: factual, little emotion; low: some emotional elements; moderate: clear emotional component; high: strong emotional content; intense: overwhelming emotional content"
      
    field :agent_label, type: :string, required: false,
      examples: ["Research Participant A", "Community Member", "Dr. Johnson", "Anonymous", "Field Team Leader"],
      hints: "Who experienced this (name, role, or identifier) - USE ANONYMOUS/ROLE WHEN PRIVACY REQUIRED"
      
    field :context, type: :text, required: false,
      examples: [
        "During Arctic research expedition in Svalbard, summer 2023",
        "Community planning meeting for climate adaptation",
        "Post-storm assessment of research infrastructure"
      ],
      hints: "Setting, circumstances, or background context where this experience occurred"
      
    field :narrative_text, type: :text, required: true,
      examples: [
        "Observed significant changes in sea ice patterns during the monitoring period",
        "Community members expressed concerns about traditional knowledge integration", 
        "Equipment performed well under extreme cold conditions, with minor adjustments needed"
      ],
      hints: "The actual experience content - REDACT PERSONAL IDENTIFIERS IF PRIVACY_LEVEL REQUIRES"
      
    field :observed_at, type: :datetime, required: true,
      examples: ["2023-08-15T14:30:00Z", "2023-07-22T09:15:00Z"],
      hints: "When this experience occurred - ISO datetime format"
  end
  
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
