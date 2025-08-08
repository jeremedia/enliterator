# frozen_string_literal: true

# == Schema Information
#
# Table name: manifest_spatials
#
#  id            :bigint           not null, primary key
#  manifest_id   :bigint           not null
#  spatial_id    :bigint           not null
#  relation_type :string           default("located_at")
#  strength      :float
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
# Indexes
#
#  index_manifest_spatials_on_manifest_id                 (manifest_id)
#  index_manifest_spatials_on_manifest_id_and_spatial_id  (manifest_id,spatial_id) UNIQUE
#  index_manifest_spatials_on_spatial_id                  (spatial_id)
#
class ManifestSpatial < ApplicationRecord
  belongs_to :manifest
  belongs_to :spatial
  
  validates :manifest_id, uniqueness: { scope: :spatial_id }
  validates :strength, numericality: { in: 0..1 }, allow_nil: true
end
