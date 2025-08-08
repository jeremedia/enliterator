# frozen_string_literal: true

# Join table for Evidence-Experience relationships
class EvidenceExperience < ApplicationRecord
  belongs_to :evidence
  belongs_to :experience
  
  validates :evidence_id, uniqueness: { scope: :experience_id }
  validates :strength, numericality: { in: 0..1 }, allow_nil: true
end