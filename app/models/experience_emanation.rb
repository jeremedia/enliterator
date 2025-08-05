# frozen_string_literal: true

# Join table for Experiences and Emanations
class ExperienceEmanation < ApplicationRecord
  belongs_to :experience
  belongs_to :emanation
  
  validates :experience_id, uniqueness: { scope: :emanation_id }
end