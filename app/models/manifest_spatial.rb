# frozen_string_literal: true

# Join table for Manifest-Spatial relationships
class ManifestSpatial < ApplicationRecord
  belongs_to :manifest
  belongs_to :spatial
  
  validates :manifest_id, uniqueness: { scope: :spatial_id }
  validates :strength, numericality: { in: 0..1 }, allow_nil: true
end