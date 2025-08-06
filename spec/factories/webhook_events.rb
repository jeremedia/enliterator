FactoryBot.define do
  factory :webhook_event do
    event_id { "MyString" }
    event_type { "MyString" }
    webhook_id { "MyString" }
    timestamp { "2025-08-06 07:49:19" }
    signature { "MyString" }
    headers { "" }
    payload { "" }
    status { "MyString" }
    processed_at { "2025-08-06 07:49:19" }
    error_message { "MyText" }
    metadata { "" }
  end
end
