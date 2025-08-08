# frozen_string_literal: true

# Join table for MethodPool-Practical relationships
class MethodPoolPractical < ApplicationRecord
  belongs_to :method_pool
  belongs_to :practical
  
  validates :method_pool_id, uniqueness: { scope: :practical_id }
  validates :strength, numericality: { in: 0..1 }, allow_nil: true
end