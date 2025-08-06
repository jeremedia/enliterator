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
