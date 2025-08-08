# frozen_string_literal: true

# == Schema Information
#
# Table name: experience_emanations
#
#  id            :bigint           not null, primary key
#  experience_id :bigint           not null
#  emanation_id  :bigint           not null
#  relation_type :string           default("inspires")
#  strength      :float
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
# Indexes
#
#  index_experience_emanations_on_emanation_id                    (emanation_id)
#  index_experience_emanations_on_experience_id                   (experience_id)
#  index_experience_emanations_on_experience_id_and_emanation_id  (experience_id,emanation_id) UNIQUE
#
# Join table for Experiences and Emanations
class ExperienceEmanation < ApplicationRecord
  belongs_to :experience
  belongs_to :emanation
  
  validates :experience_id, uniqueness: { scope: :emanation_id }
end
