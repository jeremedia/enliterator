# frozen_string_literal: true

# Join table for Actor-Manifest relationships
class ActorManifest < ApplicationRecord
  belongs_to :actor
  belongs_to :manifest
  
  validates :actor_id, uniqueness: { scope: :manifest_id }
  validates :strength, numericality: { in: 0..1 }, allow_nil: true
end