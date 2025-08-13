# frozen_string_literal: true

# == Schema Information
#
# Table name: practicals
#
#  id                       :bigint           not null, primary key
#  goal                     :string           not null
#  steps                    :jsonb
#  prerequisites            :jsonb
#  hazards                  :jsonb
#  validation_refs          :jsonb
#  repr_text                :text             not null
#  provenance_and_rights_id :bigint           not null
#  valid_time_start         :datetime         not null
#  valid_time_end           :datetime
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#
# Indexes
#
#  index_practicals_on_goal                                 (goal)
#  index_practicals_on_provenance_and_rights_id             (provenance_and_rights_id)
#  index_practicals_on_steps                                (steps) USING gin
#  index_practicals_on_valid_time_start_and_valid_time_end  (valid_time_start,valid_time_end)
#
class Practical < ApplicationRecord
  include EknPoolEntity

  # Enums for procedural knowledge classification
  enum :skill_level, {
    beginner: 0,        # No prior experience required
    intermediate: 1,    # Some basic knowledge assumed
    advanced: 2,        # Significant expertise required
    expert: 3,          # Deep domain knowledge needed
    professional: 4     # Professional/certified level
  }, prefix: true

  enum :domain, {
    research: 0,        # Scientific research methods
    technical: 1,       # Engineering, technical procedures
    administrative: 2,  # Management, bureaucratic processes
    educational: 3,     # Teaching, training methodologies
    safety: 4,          # Safety protocols, risk management
    environmental: 5,   # Environmental procedures, conservation
    social: 6,          # Community organizing, social practices
    creative: 7         # Arts, design, creative processes
  }, prefix: true

  enum :instruction_type, {
    step_by_step: 0,    # Sequential numbered steps
    checklist: 1,       # Items to verify/complete
    flowchart: 2,       # Decision-based process flow
    narrative: 3,       # Story-like explanation
    visual: 4,          # Diagram or image-based
    interactive: 5,     # Hands-on, guided practice
    template: 6,        # Fill-in-the-blank format
    example: 7          # Learn through examples
  }, prefix: true

  enum :validation_method, {
    self_check: 0,      # Individual verification
    peer_review: 1,     # Colleague/partner check
    automated_test: 2,  # System/tool validation
    expert_validation: 3, # Professional verification
    outcome_based: 4,   # Success measured by results
    time_based: 5       # Completion within timeframe
  }, prefix: true

  enum :complexity_level, {
    simple: 0,          # Single task, few dependencies
    moderate: 1,        # Multiple steps, some coordination
    complex: 2,         # Many variables, careful planning
    very_complex: 3,    # High coordination, many dependencies
    expert_only: 4      # Extreme complexity, specialist knowledge
  }, prefix: true

  # Model-driven extraction configuration
  extraction_config do
    canonical_name "Practical"
    description "How-to knowledge, procedures, tacit knowledge - actionable procedural information"
    
    field :goal, type: :string, required: true,
      examples: [
        "Set up Arctic research weather station",
        "Conduct community resilience assessment",
        "Implement climate data collection protocol",
        "Organize participatory planning workshop",
        "Deploy remote sensing equipment safely"
      ],
      hints: "The objective or outcome that this procedure aims to achieve"
      
    field :skill_level, type: :enum,
      values: -> { skill_levels.keys },  # Live from model enum - 5 values!
      default: 'intermediate',
      hints: "beginner: no experience required; intermediate: basic knowledge; advanced: significant expertise; expert: deep domain knowledge; professional: certified level"
      
    field :domain, type: :enum,
      values: -> { domains.keys },  # Live from model enum - 8 values!
      default: 'research',
      hints: "research: scientific methods; technical: engineering; administrative: management; educational: teaching; safety: protocols; environmental: conservation; social: community; creative: arts/design"
      
    field :instruction_type, type: :enum,
      values: -> { instruction_types.keys },  # Live from model enum - 8 values!
      default: 'step_by_step',
      hints: "step_by_step: sequential steps; checklist: verification items; flowchart: decision-based; narrative: story explanation; visual: diagram-based; interactive: hands-on; template: fill-in-blank; example: learn by examples"
      
    field :validation_method, type: :enum,
      values: -> { validation_methods.keys },  # Live from model enum - 6 values!
      default: 'outcome_based',
      hints: "self_check: individual verification; peer_review: colleague check; automated_test: system validation; expert_validation: professional review; outcome_based: results-measured; time_based: completion timeframe"
      
    field :complexity_level, type: :enum,
      values: -> { complexity_levels.keys },  # Live from model enum - 5 values!
      default: 'moderate',
      hints: "simple: single task; moderate: multiple steps; complex: many variables; very_complex: high coordination; expert_only: extreme complexity"
      
    field :steps, type: :json, required: false,
      examples: [
        ["Gather equipment list", "Check weather conditions", "Travel to site", "Install monitoring hardware", "Test data transmission"],
        ["Review community demographics", "Prepare survey instruments", "Schedule focus groups", "Conduct interviews", "Analyze responses", "Present findings"],
        ["Calibrate instruments", "Establish baseline measurements", "Document protocols", "Train field team", "Begin data collection"]
      ],
      hints: "Array of sequential steps or procedures to accomplish the goal"
      
    field :prerequisites, type: :json, required: false,
      examples: [
        ["Basic electronics knowledge", "Cold weather gear", "Transportation to remote sites"],
        ["Survey design experience", "Community liaison contacts", "Data analysis software"],
        ["Scientific instrumentation training", "Safety certification", "Research permits"]
      ],
      hints: "Array of required knowledge, skills, equipment, or conditions needed before starting"
      
    field :hazards, type: :json, required: false,
      examples: [
        ["Extreme cold exposure", "Equipment failure in remote location", "Wildlife encounters"],
        ["Cultural sensitivity issues", "Data privacy concerns", "Participant bias"],
        ["Instrument malfunction", "Weather delays", "Budget overruns"]
      ],
      hints: "Array of risks, dangers, or potential problems to be aware of during execution"
  end

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
  # Allow empty steps for extracted entities - they can be refined later
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
