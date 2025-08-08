# frozen_string_literal: true

# Join table for Practical-Idea relationships (reverse of Idea->Practical)
class PracticalIdea < ApplicationRecord
  belongs_to :practical
  belongs_to :idea
  
  validates :practical_id, uniqueness: { scope: :idea_id }
  validates :strength, numericality: { in: 0..1 }, allow_nil: true
end