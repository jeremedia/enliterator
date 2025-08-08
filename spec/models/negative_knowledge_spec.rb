# == Schema Information
#
# Table name: negative_knowledges
#
#  id                    :bigint           not null, primary key
#  batch_id              :bigint
#  gap_type              :string
#  gap_description       :text
#  severity              :string
#  affected_pools        :text
#  impact                :text
#  suggested_remediation :text
#  metadata              :jsonb
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#
# Indexes
#
#  index_negative_knowledges_on_batch_id  (batch_id)
#
require 'rails_helper'

RSpec.describe NegativeKnowledge, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
