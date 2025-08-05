# frozen_string_literal: true

# Join table for Manifests and Experiences
class ManifestExperience < ApplicationRecord
  belongs_to :manifest
  belongs_to :experience
  
  validates :manifest_id, uniqueness: { scope: :experience_id }
end