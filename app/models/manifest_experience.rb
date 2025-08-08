# frozen_string_literal: true

# == Schema Information
#
# Table name: manifest_experiences
#
#  id            :bigint           not null, primary key
#  manifest_id   :bigint           not null
#  experience_id :bigint           not null
#  relation_type :string           default("elicits")
#  strength      :float
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
# Indexes
#
#  index_manifest_experiences_on_experience_id                  (experience_id)
#  index_manifest_experiences_on_manifest_id                    (manifest_id)
#  index_manifest_experiences_on_manifest_id_and_experience_id  (manifest_id,experience_id) UNIQUE
#
# Join table for Manifests and Experiences
class ManifestExperience < ApplicationRecord
  belongs_to :manifest
  belongs_to :experience
  
  validates :manifest_id, uniqueness: { scope: :experience_id }
end
