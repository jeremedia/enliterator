# frozen_string_literal: true

# == Schema Information
#
# Table name: experience_practicals
#
#  id            :bigint           not null, primary key
#  experience_id :bigint           not null
#  practical_id  :bigint           not null
#  relation_type :string
#  strength      :float
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
# Indexes
#
#  index_exp_prac_on_ids_and_type                (experience_id,practical_id,relation_type) UNIQUE
#  index_experience_practicals_on_experience_id  (experience_id)
#  index_experience_practicals_on_practical_id   (practical_id)
#
class ExperiencePractical < ApplicationRecord
  belongs_to :experience
  belongs_to :practical
  
  validates :experience_id, uniqueness: { scope: :practical_id }
  validates :strength, numericality: { in: 0..1 }, allow_nil: true
end
