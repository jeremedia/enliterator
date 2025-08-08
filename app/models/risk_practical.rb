# frozen_string_literal: true

# Join table for Risk-Practical relationships
class RiskPractical < ApplicationRecord
  belongs_to :risk
  belongs_to :practical
  
  validates :risk_id, uniqueness: { scope: :practical_id }
  validates :strength, numericality: { in: 0..1 }, allow_nil: true
end