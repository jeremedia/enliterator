# == Schema Information
#
# Table name: conversation_histories
#
#  id              :bigint           not null, primary key
#  conversation_id :string
#  user_id         :string
#  role            :string
#  content         :text
#  metadata        :jsonb
#  position        :integer
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#
# Indexes
#
#  index_conversation_histories_on_conversation_id  (conversation_id)
#
FactoryBot.define do
  factory :conversation_history do
    conversation_id { "MyString" }
    user_id { "MyString" }
    role { "MyString" }
    content { "MyText" }
    metadata { "" }
    position { 1 }
  end
end
