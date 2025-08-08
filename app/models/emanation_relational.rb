# frozen_string_literal: true

# == Schema Information
#
# Table name: emanation_relationals
#
#  id            :bigint           not null, primary key
#  emanation_id  :bigint           not null
#  relational_id :bigint           not null
#  relation_type :string           default("diffuses_through")
#  strength      :float
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
# Indexes
#
#  index_emanation_relationals_on_emanation_id                    (emanation_id)
#  index_emanation_relationals_on_emanation_id_and_relational_id  (emanation_id,relational_id) UNIQUE
#  index_emanation_relationals_on_relational_id                   (relational_id)
#
class EmanationRelational < ApplicationRecord
  belongs_to :emanation
  belongs_to :relational
  
  validates :emanation_id, uniqueness: { scope: :relational_id }
  validates :strength, numericality: { in: 0..1 }, allow_nil: true
end
