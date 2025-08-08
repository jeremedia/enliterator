# == Schema Information
#
# Table name: messages
#
#  id              :bigint           not null, primary key
#  conversation_id :bigint           not null
#  role            :integer
#  content         :text
#  metadata        :jsonb
#  tokens_used     :integer
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#
# Indexes
#
#  index_messages_on_conversation_id  (conversation_id)
#
FactoryBot.define do
  factory :message do
    conversation { nil }
    role { 1 }
    content { "MyText" }
    metadata { "" }
    tokens_used { 1 }
  end
end
