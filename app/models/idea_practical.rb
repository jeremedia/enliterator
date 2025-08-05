# frozen_string_literal: true

# Join table for Ideas and Practicals (codifies relation)
class IdeaPractical < ApplicationRecord
  belongs_to :idea
  belongs_to :practical
  
  # Optional: Add validation to prevent duplicates
  validates :idea_id, uniqueness: { scope: :practical_id }
end