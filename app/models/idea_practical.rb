# frozen_string_literal: true

# == Schema Information
#
# Table name: idea_practicals
#
#  id            :bigint           not null, primary key
#  idea_id       :bigint           not null
#  practical_id  :bigint           not null
#  relation_type :string           default("codifies")
#  strength      :float
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
# Indexes
#
#  index_idea_practicals_on_idea_id                   (idea_id)
#  index_idea_practicals_on_idea_id_and_practical_id  (idea_id,practical_id) UNIQUE
#  index_idea_practicals_on_practical_id              (practical_id)
#
# Join table for Ideas and Practicals (codifies relation)
class IdeaPractical < ApplicationRecord
  belongs_to :idea
  belongs_to :practical
  
  # Optional: Add validation to prevent duplicates
  validates :idea_id, uniqueness: { scope: :practical_id }
end
