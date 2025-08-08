# == Schema Information
#
# Table name: conversations
#
#  id               :bigint           not null, primary key
#  ingest_batch_id  :bigint
#  context          :jsonb
#  model_config     :jsonb
#  status           :string
#  expertise_level  :string
#  last_activity_at :datetime
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  ekn_id           :bigint
#
# Indexes
#
#  index_conversations_on_ekn_id            (ekn_id)
#  index_conversations_on_ingest_batch_id   (ingest_batch_id)
#  index_conversations_on_last_activity_at  (last_activity_at)
#  index_conversations_on_status            (status)
#
FactoryBot.define do
  factory :conversation do
    user { nil }
    ingest_batch { nil }
    context { "" }
    status { "MyString" }
    expertise_level { "MyString" }
    last_activity_at { "2025-08-05 19:02:22" }
  end
end
