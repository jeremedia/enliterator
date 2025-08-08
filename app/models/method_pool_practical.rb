# frozen_string_literal: true

# == Schema Information
#
# Table name: method_pool_practicals
#
#  id             :bigint           not null, primary key
#  method_pool_id :bigint           not null
#  practical_id   :bigint           not null
#  relation_type  :string           default("implements")
#  strength       :float
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#
# Indexes
#
#  idx_on_method_pool_id_practical_id_0f0229a2ca   (method_pool_id,practical_id) UNIQUE
#  index_method_pool_practicals_on_method_pool_id  (method_pool_id)
#  index_method_pool_practicals_on_practical_id    (practical_id)
#
class MethodPoolPractical < ApplicationRecord
  belongs_to :method_pool
  belongs_to :practical
  
  validates :method_pool_id, uniqueness: { scope: :practical_id }
  validates :strength, numericality: { in: 0..1 }, allow_nil: true
end
