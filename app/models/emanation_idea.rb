# frozen_string_literal: true

# Join table for Emanation-Idea relationships
class EmanationIdea < ApplicationRecord
  belongs_to :emanation
  belongs_to :idea
  
  validates :emanation_id, uniqueness: { scope: :idea_id }
  validates :strength, numericality: { in: 0..1 }, allow_nil: true
end