# == Schema Information
#
# Table name: webhook_events
#
#  id            :bigint           not null, primary key
#  event_id      :string           not null
#  event_type    :string           not null
#  webhook_id    :string           not null
#  timestamp     :datetime         not null
#  signature     :string
#  headers       :jsonb
#  payload       :jsonb            not null
#  status        :string           default("pending"), not null
#  processed_at  :datetime
#  error_message :text
#  metadata      :jsonb
#  retry_count   :integer          default(0)
#  resource_type :string
#  resource_id   :string
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
# Indexes
#
#  index_webhook_events_on_created_at                     (created_at)
#  index_webhook_events_on_event_id                       (event_id) UNIQUE
#  index_webhook_events_on_event_type                     (event_type)
#  index_webhook_events_on_resource_type_and_resource_id  (resource_type,resource_id)
#  index_webhook_events_on_status                         (status)
#  index_webhook_events_on_webhook_id                     (webhook_id)
#
require 'rails_helper'

RSpec.describe WebhookEvent, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
