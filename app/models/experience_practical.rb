# frozen_string_literal: true

# Join table for Experience-Practical relationships
class ExperiencePractical < ApplicationRecord
  belongs_to :experience
  belongs_to :practical
  
  validates :experience_id, uniqueness: { scope: :practical_id }
  validates :strength, numericality: { in: 0..1 }, allow_nil: true
end