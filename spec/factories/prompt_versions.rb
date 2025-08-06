FactoryBot.define do
  factory :prompt_version do
    prompt { nil }
    content { "MyText" }
    variables { "" }
    status { 1 }
    version_number { 1 }
    performance_score { 1.5 }
  end
end
