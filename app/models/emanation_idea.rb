# frozen_string_literal: true

# == Schema Information
#
# Table name: emanation_ideas
#
#  id            :bigint           not null, primary key
#  emanation_id  :bigint           not null
#  idea_id       :bigint           not null
#  relation_type :string
#  strength      :float
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
# Indexes
#
#  index_eman_idea_on_ids_and_type        (emanation_id,idea_id,relation_type) UNIQUE
#  index_emanation_ideas_on_emanation_id  (emanation_id)
#  index_emanation_ideas_on_idea_id       (idea_id)
#
# Join table for Emanation-Idea relationships
class EmanationIdea < ApplicationRecord
  belongs_to :emanation
  belongs_to :idea
  
  validates :emanation_id, uniqueness: { scope: :idea_id }
  validates :strength, numericality: { in: 0..1 }, allow_nil: true
end
