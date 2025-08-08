# == Schema Information
#
# Table name: interview_sessions
#
#  id         :bigint           not null, primary key
#  session_id :string
#  data       :jsonb
#  completed  :boolean
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_interview_sessions_on_session_id  (session_id)
#
FactoryBot.define do
  factory :interview_session do
    session_id { "MyString" }
    data { "" }
    completed { false }
  end
end
