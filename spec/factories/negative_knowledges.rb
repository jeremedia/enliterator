FactoryBot.define do
  factory :negative_knowledge do
    batch { nil }
    gap_type { "MyString" }
    gap_description { "MyText" }
    severity { "MyString" }
    affected_pools { "MyText" }
    impact { "MyText" }
    suggested_remediation { "MyText" }
    metadata { "" }
  end
end
