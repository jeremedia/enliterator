FactoryBot.define do
  factory :prompt do
    key { "MyString" }
    name { "MyString" }
    description { "MyText" }
    category { 1 }
    context { 1 }
    active { false }
    current_version_id { 1 }
  end
end
