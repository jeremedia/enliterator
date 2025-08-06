FactoryBot.define do
  factory :message do
    conversation { nil }
    role { 1 }
    content { "MyText" }
    metadata { "" }
    tokens_used { 1 }
  end
end
