# frozen_string_literal: true

# == Schema Information
#
# Table name: idea_emanations
#
#  id            :bigint           not null, primary key
#  idea_id       :bigint           not null
#  emanation_id  :bigint           not null
#  relation_type :string           default("influences")
#  strength      :float
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
# Indexes
#
#  index_idea_emanations_on_emanation_id              (emanation_id)
#  index_idea_emanations_on_idea_id                   (idea_id)
#  index_idea_emanations_on_idea_id_and_emanation_id  (idea_id,emanation_id) UNIQUE
#
class IdeaEmanation < ApplicationRecord
  belongs_to :idea
  belongs_to :emanation
  
  # Optional: Add validation to prevent duplicates
  validates :idea_id, uniqueness: { scope: :emanation_id }
end
