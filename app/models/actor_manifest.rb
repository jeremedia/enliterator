# frozen_string_literal: true

# == Schema Information
#
# Table name: actor_manifests
#
#  id            :bigint           not null, primary key
#  actor_id      :bigint           not null
#  manifest_id   :bigint           not null
#  relation_type :string           default("interacts_with")
#  strength      :float
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
# Indexes
#
#  index_actor_manifests_on_actor_id                  (actor_id)
#  index_actor_manifests_on_actor_id_and_manifest_id  (actor_id,manifest_id) UNIQUE
#  index_actor_manifests_on_manifest_id               (manifest_id)
#
# Join table for Actor-Manifest relationships
class ActorManifest < ApplicationRecord
  belongs_to :actor
  belongs_to :manifest
  
  validates :actor_id, uniqueness: { scope: :manifest_id }
  validates :strength, numericality: { in: 0..1 }, allow_nil: true
end
