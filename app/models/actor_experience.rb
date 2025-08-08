# frozen_string_literal: true

# Join table for Actor-Experience relationships
class ActorExperience < ApplicationRecord
  belongs_to :actor
  belongs_to :experience
  
  validates :actor_id, uniqueness: { scope: :experience_id }
  validates :strength, numericality: { in: 0..1 }, allow_nil: true
end