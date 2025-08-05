# frozen_string_literal: true

# Join table for Ideas and Emanations (influences relation)
class IdeaEmanation < ApplicationRecord
  belongs_to :idea
  belongs_to :emanation
  
  # Optional: Add validation to prevent duplicates
  validates :idea_id, uniqueness: { scope: :emanation_id }
end