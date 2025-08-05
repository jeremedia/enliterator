# frozen_string_literal: true

# Practical pool: how-to guides, instructions, and procedures
class Practical < ApplicationRecord
  include HasRights
  include TimeTrackable

  # Associations through join tables
  has_many :idea_practicals, dependent: :destroy
  has_many :ideas, through: :idea_practicals
  has_many :experience_practicals, dependent: :destroy
  has_many :experiences, through: :experience_practicals
  has_many :practical_ideas, dependent: :destroy
  has_many :derived_ideas, through: :practical_ideas, source: :idea

  # Validations
  validates :goal, presence: true
  validates :repr_text, presence: true, length: { maximum: 500 }
  validates :steps, presence: true
  validate :steps_array_valid

  # Scopes
  scope :by_goal, ->(goal) { where("goal ILIKE ?", "%#{goal}%") }
  scope :with_prerequisites, -> { where.not(prerequisites: []) }
  scope :beginner_friendly, -> { where("jsonb_array_length(prerequisites) = 0") }
  scope :with_hazards, -> { where("jsonb_array_length(hazards) > 0") }

  # Callbacks
  before_validation :normalize_arrays
  before_validation :generate_repr_text
  after_commit :sync_to_graph, on: [:create, :update]
  after_commit :remove_from_graph, on: :destroy

  # Instance methods
  def step_count
    steps.size
  end

  def estimated_duration
    # Could be calculated from steps or stored explicitly
    metadata&.dig("estimated_minutes")
  end

  def difficulty_level
    return "beginner" if prerequisites.blank?
    return "advanced" if prerequisites.size > 3
    "intermediate"
  end

  def complete_prerequisites
    # Expand prerequisite IDs to full objects if needed
    prerequisites.map do |prereq|
      if prereq.is_a?(String) && prereq.match?(/\A\d+\z/)
        Practical.find_by(id: prereq)
      else
        prereq
      end
    end.compact
  end

  private

  def normalize_arrays
    self.steps = [] if steps.nil?
    self.prerequisites = [] if prerequisites.nil?
    self.hazards = [] if hazards.nil?
    self.validation_refs = [] if validation_refs.nil?
  end

  def steps_array_valid
    return if steps.blank?

    unless steps.is_a?(Array) && steps.all? { |step| step.is_a?(String) || step.is_a?(Hash) }
      errors.add(:steps, "must be an array of strings or structured steps")
    end
  end

  def generate_repr_text
    step_summary = if steps.is_a?(Array) && steps.any?
                     first_step = steps.first.is_a?(Hash) ? steps.first["description"] : steps.first
                     "#{step_count} steps: #{first_step.to_s.truncate(50)}..."
                   else
                     "No steps defined"
                   end
    
    self.repr_text = "How to #{goal}: #{step_summary}"
  end

  def sync_to_graph
    Graph::PracticalWriter.new(self).sync
  rescue StandardError => e
    Rails.logger.error "Failed to sync Practical #{id} to graph: #{e.message}"
  end

  def remove_from_graph
    Graph::PracticalRemover.new(self).remove
  rescue StandardError => e
    Rails.logger.error "Failed to remove Practical #{id} from graph: #{e.message}"
  end
end