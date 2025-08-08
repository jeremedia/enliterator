# frozen_string_literal: true

# == Schema Information
#
# Table name: idea_manifests
#
#  id            :bigint           not null, primary key
#  idea_id       :bigint           not null
#  manifest_id   :bigint           not null
#  relation_type :string           default("embodies")
#  strength      :float
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
# Indexes
#
#  index_idea_manifests_on_idea_id                  (idea_id)
#  index_idea_manifests_on_idea_id_and_manifest_id  (idea_id,manifest_id) UNIQUE
#  index_idea_manifests_on_manifest_id              (manifest_id)
#
class IdeaManifest < ApplicationRecord
  belongs_to :idea
  belongs_to :manifest
  
  # Optional: Add validation to prevent duplicates
  validates :idea_id, uniqueness: { scope: :manifest_id }
end
