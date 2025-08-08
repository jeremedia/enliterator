# frozen_string_literal: true

# == Schema Information
#
# Table name: practical_ideas
#
#  id            :bigint           not null, primary key
#  practical_id  :bigint           not null
#  idea_id       :bigint           not null
#  relation_type :string
#  strength      :float
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
# Indexes
#
#  index_prac_idea_on_ids_and_type        (practical_id,idea_id,relation_type) UNIQUE
#  index_practical_ideas_on_idea_id       (idea_id)
#  index_practical_ideas_on_practical_id  (practical_id)
#
class PracticalIdea < ApplicationRecord
  belongs_to :practical
  belongs_to :idea
  
  validates :practical_id, uniqueness: { scope: :idea_id }
  validates :strength, numericality: { in: 0..1 }, allow_nil: true
end
