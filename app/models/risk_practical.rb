# frozen_string_literal: true

# == Schema Information
#
# Table name: risk_practicals
#
#  id            :bigint           not null, primary key
#  risk_id       :bigint           not null
#  practical_id  :bigint           not null
#  relation_type :string           default("mitigated_by")
#  strength      :float
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
# Indexes
#
#  index_risk_practicals_on_practical_id              (practical_id)
#  index_risk_practicals_on_risk_id                   (risk_id)
#  index_risk_practicals_on_risk_id_and_practical_id  (risk_id,practical_id) UNIQUE
#
class RiskPractical < ApplicationRecord
  belongs_to :risk
  belongs_to :practical
  
  validates :risk_id, uniqueness: { scope: :practical_id }
  validates :strength, numericality: { in: 0..1 }, allow_nil: true
end
