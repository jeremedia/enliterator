# frozen_string_literal: true

# Join table for Ideas and Manifests
class IdeaManifest < ApplicationRecord
  belongs_to :idea
  belongs_to :manifest
  
  # Optional: Add validation to prevent duplicates
  validates :idea_id, uniqueness: { scope: :manifest_id }
end