# frozen_string_literal: true

# == Schema Information
#
# Table name: evolutionaries
#
#  id                       :bigint           not null, primary key
#  change_note              :text             not null
#  prior_ref_type           :string
#  prior_ref_id             :bigint
#  version_id               :string
#  refined_idea_id          :bigint
#  manifest_version_id      :bigint
#  provenance_and_rights_id :bigint           not null
#  valid_time_start         :datetime         not null
#  valid_time_end           :datetime
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  repr_text                :text             not null
#  change_summary           :text             not null
#  delta_metrics            :jsonb
#
# Indexes
#
#  index_evolutionaries_on_manifest_version_id                  (manifest_version_id)
#  index_evolutionaries_on_prior_ref                            (prior_ref_type,prior_ref_id)
#  index_evolutionaries_on_prior_ref_type_and_prior_ref_id      (prior_ref_type,prior_ref_id)
#  index_evolutionaries_on_provenance_and_rights_id             (provenance_and_rights_id)
#  index_evolutionaries_on_refined_idea_id                      (refined_idea_id)
#  index_evolutionaries_on_valid_time_start_and_valid_time_end  (valid_time_start,valid_time_end)
#  index_evolutionaries_on_version_id                           (version_id)
#
class Evolutionary < ApplicationRecord
  include EknPoolEntity

  # Note: Change magnitude and type are stored in delta_metrics JSON field
  # This provides flexibility without requiring database schema changes

  # Polymorphic association to what was changed (EknPoolEntity provides provenance_and_rights)
  belongs_to :prior_ref, polymorphic: true, optional: true

  # Model-driven extraction configuration
  extraction_config do
    canonical_name "Evolutionary"
    description "Change over time, temporal patterns, development - evolution tracking"
    
    field :version_id, type: :string, required: true,
      examples: ["v1.0", "v2.1.3", "2023-08-15", "iteration-5", "draft-final"],
      hints: "Version identifier for tracking sequential changes (semantic versioning, dates, or iteration numbers)"
      
    field :change_summary, type: :text, required: true,
      examples: [
        "Updated climate model parameters based on new Arctic data",
        "Refined research methodology to include additional data sources", 
        "Consolidated multiple risk assessments into comprehensive framework",
        "Transformed data collection approach from manual to automated"
      ],
      hints: "Brief description of what changed and why"
      
    # Note: change_magnitude and change_type are captured in delta_metrics JSON
      
    field :prior_ref_type, type: :string, required: false,
      examples: ["Actor", "Spatial", "Evidence", "Risk", "Idea", "Manifest"],
      hints: "The type of entity that was changed (what evolved FROM)"
      
    field :prior_ref_id, type: :integer, required: false,
      examples: [15, 42, 127, 298],
      hints: "The database ID of the entity that was changed"
      
    field :delta_metrics, type: :json, required: false,
      examples: [
        {"magnitude": "moderate", "type": "refinement", "lines_added": 45, "lines_removed": 12},
        {"magnitude": "major", "type": "transformation", "sections_modified": 3, "new_concepts": 7},
        {"magnitude": "minor", "type": "expansion", "features_added": 2, "complexity_delta": 0.1}
      ],
      hints: "Change metrics including magnitude (trivial/minor/moderate/major/revolutionary), type (refinement/expansion/consolidation/pivot/transformation/deprecation/revival), and quantitative measures"
  end

  # Additional validations (EknPoolEntity provides common ones) 
  validates :change_summary, presence: true, length: { maximum: 2000 }
  
  # Scopes
  scope :for_entity, ->(entity) { where(prior_ref: entity) }
  scope :by_version, -> { order(version_id: :asc) }
  scope :recent_changes, -> { order(valid_time_start: :desc).limit(10) }

  # Callbacks (EknPoolEntity provides sync_to_graph)
  before_validation :generate_repr_text

  # Instance methods
  def major_version?
    magnitude = delta_metrics&.dig("magnitude")
    magnitude == "major" || magnitude == "revolutionary"
  end
  
  def change_magnitude
    delta_metrics&.dig("magnitude") || "unknown"
  end
  
  def change_type
    delta_metrics&.dig("type") || "unknown"
  end

  def prior_entity
    prior_ref
  end

  def next_versions
    self.class.where(prior_ref: self).by_version
  end

  def version_chain
    # Traverse the version history
    chain = [self]
    current = self
    
    while current.prior_ref.present?
      break if current.prior_ref.is_a?(Evolutionary)
      current = current.prior_ref
      chain.unshift(current) if current.respond_to?(:evolutionaries)
    end
    
    chain
  end

  private

  def generate_repr_text
    entity_label = if prior_ref
                     "#{prior_ref.class.name}(#{prior_ref.try(:label) || prior_ref.id})"
                   else
                     "Initial"
                   end
    
    magnitude_text = change_magnitude.present? ? " [#{change_magnitude.upcase}]" : ""
    self.repr_text = "Evolution v#{version_id}: #{entity_label} → #{change_summary.truncate(80)}#{magnitude_text}"
  end
end
