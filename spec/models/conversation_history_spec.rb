# == Schema Information
#
# Table name: conversation_histories
#
#  id              :bigint           not null, primary key
#  conversation_id :string
#  user_id         :string
#  role            :string
#  content         :text
#  metadata        :jsonb
#  position        :integer
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#
# Indexes
#
#  index_conversation_histories_on_conversation_id  (conversation_id)
#
require 'rails_helper'

RSpec.describe ConversationHistory, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
