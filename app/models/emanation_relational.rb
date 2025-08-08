# frozen_string_literal: true

# Join table for Emanation-Relational relationships
class EmanationRelational < ApplicationRecord
  belongs_to :emanation
  belongs_to :relational
  
  validates :emanation_id, uniqueness: { scope: :relational_id }
  validates :strength, numericality: { in: 0..1 }, allow_nil: true
end