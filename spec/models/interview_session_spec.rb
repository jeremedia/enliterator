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
require 'rails_helper'

RSpec.describe InterviewSession, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
