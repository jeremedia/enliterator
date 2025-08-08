# == Schema Information
#
# Table name: prompts
#
#  id                 :bigint           not null, primary key
#  key                :string
#  name               :string
#  description        :text
#  category           :integer
#  context            :integer
#  active             :boolean
#  current_version_id :integer
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#
# Indexes
#
#  index_prompts_on_key  (key) UNIQUE
#
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
