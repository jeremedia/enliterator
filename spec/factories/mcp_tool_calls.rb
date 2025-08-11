FactoryBot.define do
  factory :mcp_tool_call do
    ekn { nil }
    conversation { nil }
    message { nil }
    tool_name { "MyString" }
    tool_id { "MyString" }
    arguments { "" }
    request_data { "" }
    response_data { "" }
    status { "MyString" }
    started_at { "2025-08-10 09:42:52" }
    completed_at { "2025-08-10 09:42:52" }
    error_message { "MyText" }
    server_label { "MyString" }
  end
end
