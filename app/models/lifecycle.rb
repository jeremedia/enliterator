# frozen_string_literal: true

# Lifecycle Pool - States, transitions, progressions, phases
# Part of the Ten Pool Canon for representing developmental sequences
class Lifecycle < ApplicationRecord
  # Relationships
  belongs_to :provenance_and_rights
  
  # Validations
  validates :label, presence: true
  validates :stage_type, presence: true
  validates :repr_text, presence: true
  validates :valid_time_start, presence: true
  
  # Enums for stage types
  enum :stage_type, {
    phase: 'phase',              # Sequential phases (Phase 1, Phase 2)
    state: 'state',              # Condition states (planning, active, complete)
    transition: 'transition',     # Change processes (melting, formation)
    cyclical: 'cyclical',        # Recurring patterns (annual cycle, seasons)
    progression: 'progression',   # Development stages (early, mature, late)
    workflow: 'workflow'         # Process steps (data collection → analysis)
  }
  
  # Scopes
  scope :by_stage_type, ->(type) { where(stage_type: type) }
  scope :by_sequence, -> { order(:sequence_order) }
  scope :active_stages, -> { where(is_active: true) }
  
  # Instance methods  
  def next_stage
    return nil unless sequence_order
    self.class.where('sequence_order > ?', sequence_order)
             .order(:sequence_order).first
  end
  
  def previous_stage
    return nil unless sequence_order
    self.class.where('sequence_order < ?', sequence_order)
             .order(sequence_order: :desc).first
  end
  
  def stage_summary
    "#{label} (#{stage_type}#{sequence_order ? " ##{sequence_order}" : ""})"
  end
end