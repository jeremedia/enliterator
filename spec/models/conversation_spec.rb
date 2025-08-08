# == Schema Information
#
# Table name: conversations
#
#  id               :bigint           not null, primary key
#  ingest_batch_id  :bigint
#  context          :jsonb
#  model_config     :jsonb
#  status           :string
#  expertise_level  :string
#  last_activity_at :datetime
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  ekn_id           :bigint
#
# Indexes
#
#  index_conversations_on_ekn_id            (ekn_id)
#  index_conversations_on_ingest_batch_id   (ingest_batch_id)
#  index_conversations_on_last_activity_at  (last_activity_at)
#  index_conversations_on_status            (status)
#
require 'rails_helper'

RSpec.describe Conversation, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
