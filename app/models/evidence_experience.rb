# frozen_string_literal: true

# == Schema Information
#
# Table name: evidence_experiences
#
#  id            :bigint           not null, primary key
#  evidence_id   :bigint           not null
#  experience_id :bigint           not null
#  relation_type :string           default("supports")
#  strength      :float
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
# Indexes
#
#  index_evidence_experiences_on_evidence_id                    (evidence_id)
#  index_evidence_experiences_on_evidence_id_and_experience_id  (evidence_id,experience_id) UNIQUE
#  index_evidence_experiences_on_experience_id                  (experience_id)
#
# Join table for Evidence-Experience relationships
class EvidenceExperience < ApplicationRecord
  belongs_to :evidence
  belongs_to :experience
  
  validates :evidence_id, uniqueness: { scope: :experience_id }
  validates :strength, numericality: { in: 0..1 }, allow_nil: true
end
