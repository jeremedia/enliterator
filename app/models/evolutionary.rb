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
  include HasRights
  include TimeTrackable

  # Polymorphic association to what was changed
  belongs_to :prior_ref, polymorphic: true, optional: true

  # Validations
  validates :version_id, presence: true
  validates :change_summary, presence: true
  validates :repr_text, presence: true, length: { maximum: 500 }
  
  # Scopes
  scope :for_entity, ->(entity) { where(prior_ref: entity) }
  scope :by_version, -> { order(version_id: :asc) }
  scope :recent_changes, -> { order(valid_time_start: :desc).limit(10) }

  # Callbacks
  before_validation :generate_repr_text
  after_commit :sync_to_graph, on: [:create, :update]
  after_commit :remove_from_graph, on: :destroy

  # Instance methods
  def major_version?
    delta_metrics.dig("magnitude") == "major" if delta_metrics.present?
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
    
    self.repr_text = "Evolution v#{version_id}: #{entity_label} → #{change_summary.truncate(100)}"
  end

  def sync_to_graph
    Graph::EvolutionaryWriter.new(self).sync
  rescue StandardError => e
    Rails.logger.error "Failed to sync Evolutionary #{id} to graph: #{e.message}"
  end

  def remove_from_graph
    Graph::EvolutionaryRemover.new(self).remove
  rescue StandardError => e
    Rails.logger.error "Failed to remove Evolutionary #{id} from graph: #{e.message}"
  end
end
