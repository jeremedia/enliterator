FactoryBot.define do
  factory :mcp_intelligent_test_run do
    mcp_test_run { nil }
    mcp_test_case { nil }
    ekn { nil }
    evaluator_type { "MyString" }
    status { "MyString" }
    agent_context { "MyText" }
    evaluation_results { "MyText" }
    started_at { "2025-08-10 14:22:04" }
    completed_at { "2025-08-10 14:22:04" }
    duration_ms { 1 }
  end
end
