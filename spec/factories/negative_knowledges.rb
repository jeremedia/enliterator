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
FactoryBot.define do
  factory :negative_knowledge do
    batch { nil }
    gap_type { "MyString" }
    gap_description { "MyText" }
    severity { "MyString" }
    affected_pools { "MyText" }
    impact { "MyText" }
    suggested_remediation { "MyText" }
    metadata { "" }
  end
end
