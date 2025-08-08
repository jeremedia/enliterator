# frozen_string_literal: true

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
class WebhookEvent < ApplicationRecord
  # Status values
  STATUSES = %w[pending processing processed failed skipped].freeze
  
  # Event types we care about
  SUPPORTED_EVENT_TYPES = %w[
    fine_tuning.job.created
    fine_tuning.job.running
    fine_tuning.job.succeeded
    fine_tuning.job.failed
    fine_tuning.job.cancelled
    batch.created
    batch.in_progress
    batch.completed
    batch.failed
    batch.cancelled
    response.completed
    response.failed
  ].freeze
  
  # Validations
  validates :event_id, presence: true, uniqueness: true
  validates :event_type, presence: true
  validates :webhook_id, presence: true
  validates :timestamp, presence: true
  validates :payload, presence: true
  validates :status, inclusion: { in: STATUSES }
  
  # Scopes
  scope :pending, -> { where(status: 'pending') }
  scope :processed, -> { where(status: 'processed') }
  scope :failed, -> { where(status: 'failed') }
  scope :recent, -> { order(created_at: :desc) }
  scope :for_resource, ->(type, id) { where(resource_type: type, resource_id: id) }
  scope :by_type, ->(event_type) { where(event_type: event_type) }
  
  # Callbacks
  before_validation :extract_resource_info, on: :create
  
  # State machine-like methods
  def mark_processing!
    update!(status: 'processing', processed_at: Time.current)
  end
  
  def mark_processed!
    update!(status: 'processed', processed_at: Time.current, error_message: nil)
  end
  
  def mark_failed!(error_message = nil)
    update!(
      status: 'failed',
      processed_at: Time.current,
      error_message: error_message,
      retry_count: retry_count + 1
    )
  end
  
  def mark_skipped!(reason = nil)
    update!(
      status: 'skipped',
      processed_at: Time.current,
      error_message: reason
    )
  end
  
  def should_retry?
    status == 'failed' && retry_count < 3
  end
  
  def fine_tuning_event?
    event_type.start_with?('fine_tuning.')
  end
  
  def batch_event?
    event_type.start_with?('batch.')
  end
  
  def response_event?
    event_type.start_with?('response.')
  end
  
  # Extract data from payload
  def data
    payload['data'] || {}
  end
  
  def openai_object_id
    data['id']
  end
  
  # Create from webhook request
  def self.create_from_request!(headers, body)
    # Parse the body if it's a string
    payload = body.is_a?(String) ? JSON.parse(body) : body
    
    create!(
      event_id: payload['id'],
      event_type: payload['type'],
      webhook_id: headers['webhook-id'] || headers['HTTP_WEBHOOK_ID'],
      timestamp: Time.at(payload['created_at'].to_i),
      signature: headers['webhook-signature'] || headers['HTTP_WEBHOOK_SIGNATURE'],
      headers: extract_webhook_headers(headers),
      payload: payload,
      status: 'pending'
    )
  end
  
  private
  
  def extract_resource_info
    return unless payload.present?
    
    # Extract resource type and ID based on event type and payload structure
    case event_type
    when /^fine_tuning\./
      self.resource_type = 'FineTuneJob'
      self.resource_id = data['id'] || data['fine_tuning_job_id']
    when /^batch\./
      self.resource_type = 'Batch'
      self.resource_id = data['id'] || data['batch_id']
    when /^response\./
      self.resource_type = 'Response'
      self.resource_id = data['id'] || data['response_id']
    end
  end
  
  def self.extract_webhook_headers(headers)
    # Extract only webhook-related headers
    webhook_headers = {}
    headers.each do |key, value|
      normalized_key = key.to_s.downcase.gsub('http_', '').gsub('_', '-')
      if normalized_key.start_with?('webhook-') || 
         normalized_key == 'user-agent' || 
         normalized_key == 'content-type'
        webhook_headers[normalized_key] = value
      end
    end
    webhook_headers
  end
end
