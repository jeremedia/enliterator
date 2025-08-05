# frozen_string_literal: true

# Evolutionary pool: versioning, iterations, and changes over time
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