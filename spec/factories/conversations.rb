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
