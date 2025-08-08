# frozen_string_literal: true

# == Schema Information
#
# Table name: actor_experiences
#
#  id            :bigint           not null, primary key
#  actor_id      :bigint           not null
#  experience_id :bigint           not null
#  relation_type :string           default("participates_in")
#  strength      :float
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
# Indexes
#
#  index_actor_experiences_on_actor_id                    (actor_id)
#  index_actor_experiences_on_actor_id_and_experience_id  (actor_id,experience_id) UNIQUE
#  index_actor_experiences_on_experience_id               (experience_id)
#
# Join table for Actor-Experience relationships
class ActorExperience < ApplicationRecord
  belongs_to :actor
  belongs_to :experience
  
  validates :actor_id, uniqueness: { scope: :experience_id }
  validates :strength, numericality: { in: 0..1 }, allow_nil: true
end
