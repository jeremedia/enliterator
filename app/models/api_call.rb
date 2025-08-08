# frozen_string_literal: true

# == Schema Information
#
# Table name: api_calls
#
#  id                 :bigint           not null, primary key
#  type               :string           not null
#  service_name       :string           not null
#  endpoint           :string           not null
#  model_used         :string
#  model_version      :string
#  request_params     :jsonb
#  response_data      :jsonb
#  response_headers   :jsonb
#  prompt_tokens      :integer
#  completion_tokens  :integer
#  total_tokens       :integer
#  cached_tokens      :integer
#  reasoning_tokens   :integer
#  image_count        :integer
#  image_size         :string
#  image_quality      :string
#  audio_duration     :float
#  voice_id           :string
#  input_cost         :decimal(12, 8)
#  output_cost        :decimal(12, 8)
#  total_cost         :decimal(12, 8)
#  currency           :string           default("USD")
#  response_time_ms   :float
#  processing_time_ms :float
#  retry_count        :integer          default(0)
#  queue_time_ms      :float
#  status             :string           default("pending"), not null
#  error_code         :string
#  error_message      :text
#  error_details      :jsonb
#  trackable_type     :string
#  trackable_id       :bigint
#  user_id            :bigint
#  request_id         :string
#  batch_id           :string
#  response_cache_key :string
#  session_id         :string
#  metadata           :jsonb
#  cached_response    :boolean          default(FALSE)
#  environment        :string
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  ekn_id             :bigint
#  response_type      :string
#
# Indexes
#
#  idx_api_calls_trackable                                    (trackable_type,trackable_id)
#  index_api_calls_on_batch_id                                (batch_id)
#  index_api_calls_on_created_at                              (created_at)
#  index_api_calls_on_ekn_id                                  (ekn_id)
#  index_api_calls_on_ekn_id_and_created_at                   (ekn_id,created_at)
#  index_api_calls_on_ekn_id_and_endpoint                     (ekn_id,endpoint)
#  index_api_calls_on_model_used                              (model_used)
#  index_api_calls_on_request_id                              (request_id)
#  index_api_calls_on_service_name                            (service_name)
#  index_api_calls_on_service_name_and_status_and_created_at  (service_name,status,created_at)
#  index_api_calls_on_session_id                              (session_id)
#  index_api_calls_on_session_id_and_created_at               (session_id,created_at)
#  index_api_calls_on_status                                  (status)
#  index_api_calls_on_trackable                               (trackable_type,trackable_id)
#  index_api_calls_on_type                                    (type)
#  index_api_calls_on_type_and_created_at                     (type,created_at)
#  index_api_calls_on_type_and_model_used_and_created_at      (type,model_used,created_at)
#  index_api_calls_on_user_id                                 (user_id)
#  index_api_calls_on_user_id_and_created_at                  (user_id,created_at)
#
class ApiCall < ApplicationRecord
  include CurrentUserTrackable
  include CurrentEknTrackable

  belongs_to :trackable, polymorphic: true, optional: true
  belongs_to :user, optional: true
  belongs_to :ekn, optional: true
  belongs_to :session, optional: true

  # Status management
  enum :status, {
    pending: "pending",
    success: "success",
    failed: "failed",
    rate_limited: "rate_limited",
    timeout: "timeout",
    cancelled: "cancelled"
  }, prefix: true

  # Scopes for analysis
  scope :recent, -> { order(created_at: :desc) }
  scope :successful, -> { where(status: "success") }
  scope :failed, -> { where(status: [ "failed", "rate_limited", "timeout" ]) }
  scope :today, -> { where(created_at: Date.current.all_day) }
  scope :yesterday, -> { where(created_at: Date.yesterday.all_day) }
  scope :this_week, -> { where(created_at: Date.current.all_week) }
  scope :this_month, -> { where(created_at: Date.current.all_month) }
  scope :by_model, ->(model) { where(model_used: model) }
  scope :by_service, ->(service) { where(service_name: service) }
  scope :by_endpoint, ->(endpoint) { where(endpoint: endpoint) }
  scope :expensive, -> { where("total_cost > ?", 0.10) }  # Calls over 10 cents

  # EKN scopes
  scope :for_ekn, ->(ekn_id) { where(ekn_id: ekn_id) }
  scope :for_session, ->(session_id) { where(session_id: session_id) }
  scope :without_ekn, -> { where(ekn_id: nil) }

  # Validations
  validates :type, presence: true
  validates :service_name, presence: true
  validates :endpoint, presence: true
  validates :status, presence: true

  # Callbacks
  before_save :calculate_total_cost
  before_save :set_environment
  after_create :check_usage_limits
  after_save :broadcast_if_expensive, if: :saved_change_to_total_cost?
  after_save :alert_on_failure, if: -> { saved_change_to_status? && failed? }

  # Class methods for provider capabilities
  class << self
    def supports_streaming?
      false  # Override in subclasses
    end

    def supports_functions?
      false  # Override in subclasses
    end

    def supports_vision?
      false  # Override in subclasses
    end

    def supports_batching?
      false  # Override in subclasses
    end

    def provider_name
      name.gsub("ApiCall", "")
    end
  end

  # Abstract methods - must be implemented by subclasses
  def calculate_costs!
    raise NotImplementedError, "#{self.class} must implement calculate_costs!"
  end

  def provider_name
    self.class.provider_name
  end

  def extract_usage_data(result)
    raise NotImplementedError, "#{self.class} must implement extract_usage_data"
  end

  # Common functionality
  def failed?
    %w[failed rate_limited timeout].include?(status)
  end

  def succeeded?
    status == "success"
  end

  def pending?
    status == "pending"
  end

  def total_time_ms
    (response_time_ms || 0) + (processing_time_ms || 0) + (queue_time_ms || 0)
  end

  def cost_per_1k_tokens
    return 0 if total_tokens.to_i == 0
    (total_cost.to_f / total_tokens) * 1000
  end

  def cost_per_1k_input_tokens
    return 0 if prompt_tokens.to_i == 0
    (input_cost.to_f / prompt_tokens) * 1000
  end

  def cost_per_1k_output_tokens
    return 0 if completion_tokens.to_i == 0
    (output_cost.to_f / completion_tokens) * 1000
  end

  # Track the API call execution
  def track_execution(&block)
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)

    begin
      result = yield(self)

      self.status = "success"
      self.response_type = result.class.name
      self.response_data = extract_response_data(result)
      extract_usage_data(result)
      calculate_costs!

      result
    rescue StandardError => e
      if e.class.name.include?("RateLimit")
        self.status = "rate_limited"
        self.error_code = "rate_limit_exceeded"
      elsif e.class.name.include?("Timeout") || e.is_a?(Net::ReadTimeout)
        self.status = "timeout"
        self.error_code = "request_timeout"
      else
        self.status = "failed"
        self.error_code = e.respond_to?(:code) ? e.code : e.class.name
      end
      self.error_message = e.message
      self.error_details = extract_error_details(e)
      raise
    ensure
      end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
      self.response_time_ms = end_time - start_time
      save!
    end
  end

  # Simplified tracking for quick calls
  def self.track(service:, endpoint:, model: nil, trackable: nil, **options, &block)
    api_call = create!(
      service_name: service,
      endpoint: endpoint,
      model_used: model,
      trackable: trackable,
      request_params: options,
      status: "pending"
    )

    api_call.track_execution(&block)
  end

  # Usage analytics
  def self.usage_summary(period = :today)
    scope = case period
    when :today then today
    when :yesterday then yesterday
    when :week then this_week
    when :month then this_month
    else all
    end

    {
      by_provider: calculate_grouped_stats(scope.group(:type)),
      by_model: calculate_grouped_stats(scope.group(:model_used)),
      by_service: calculate_grouped_stats(scope.group(:service_name)),
      by_status: scope.group(:status).count,
      total: scope.calculate_stats
    }
  end

  def self.calculate_stats
    total_count = count
    return {} if total_count == 0

    {
      count: total_count,
      total_cost: (sum(:total_cost) || 0).to_f.round(4),
      total_tokens: (sum(:total_tokens) || 0).to_i,
      avg_response_time: (average(:response_time_ms) || 0).to_f.round(2),
      avg_tokens: (average(:total_tokens) || 0).to_f.round(0),
      success_rate: (successful.count.to_f / total_count * 100).round(2),
      errors: failed.group(:error_code).count
    }.compact
  end

  def self.calculate_grouped_stats(grouped_scope)
    counts = grouped_scope.count
    costs = grouped_scope.sum(:total_cost)
    tokens = grouped_scope.sum(:total_tokens)
    avg_times = grouped_scope.average(:response_time_ms)

    result = {}
    counts.each do |key, count|
      next if key.nil?

      result[key] = {
        count: count,
        total_cost: (costs[key] || 0).to_f.round(4),
        total_tokens: (tokens[key] || 0).to_i,
        avg_response_time: (avg_times[key] || 0).to_f.round(2),
        success_rate: 100.0  # Simplified for now - would need subquery for accurate calculation
      }
    end
    result
  end

  # Cost analysis
  def self.cost_breakdown(period = :month)
    scope = period == :month ? this_month : where(created_at: period)

    {
      by_model: scope.group(:model_used).sum(:total_cost).sort_by { |_, v| -v },
      by_service: scope.group(:service_name).sum(:total_cost).sort_by { |_, v| -v },
      by_provider: scope.group(:type).sum(:total_cost),
      by_day: scope.group("DATE(created_at)").sum(:total_cost),
      most_expensive: scope.order(total_cost: :desc).limit(10).pluck(:id, :service_name, :model_used, :total_cost),
      total: scope.sum(:total_cost).to_f.round(2)
    }
  end

  # Performance metrics
  def self.performance_metrics(period = :today)
    scope = period == :today ? today : where(created_at: period)

    {
      avg_response_time: scope.average(:response_time_ms).to_f.round(2),
      p50_response_time: percentile(scope, :response_time_ms, 0.5),
      p95_response_time: percentile(scope, :response_time_ms, 0.95),
      p99_response_time: percentile(scope, :response_time_ms, 0.99),
      slowest_calls: scope.order(response_time_ms: :desc).limit(5).pluck(:id, :service_name, :endpoint, :response_time_ms),
      retry_rate: scope.where("retry_count > 0").count.to_f / scope.count * 100,
      cache_hit_rate: scope.where(cached_response: true).count.to_f / scope.count * 100
    }
  end

  # Alert thresholds
  def expensive?
    total_cost && total_cost > 0.10  # Alert for calls over 10 cents
  end

  def slow?
    response_time_ms && response_time_ms > 5000  # Alert for calls over 5 seconds
  end

  def high_token_usage?
    total_tokens && total_tokens > 4000  # Alert for high token usage
  end

  # Caching support
  def cache_key_for_request
    Digest::SHA256.hexdigest([
      endpoint,
      model_used,
      request_params.to_json
    ].join(":"))
  end

  def self.find_cached_response(endpoint:, model:, params:)
    cache_key = Digest::SHA256.hexdigest([ endpoint, model, params.to_json ].join(":"))

    successful
      .where(endpoint: endpoint, model_used: model, response_cache_key: cache_key)
      .where("created_at > ?", 1.hour.ago)
      .first
  end

  # Export for analysis
  def to_analytics_json
    {
      id: id,
      provider: provider_name,
      service: service_name,
      endpoint: endpoint,
      model: model_used,
      tokens: {
        prompt: prompt_tokens,
        completion: completion_tokens,
        total: total_tokens,
        cached: cached_tokens
      },
      cost: {
        input: input_cost,
        output: output_cost,
        total: total_cost,
        currency: currency
      },
      performance: {
        response_time_ms: response_time_ms,
        queue_time_ms: queue_time_ms,
        total_time_ms: total_time_ms
      },
      status: status,
      error: error_code,
      timestamp: created_at
    }
  end

  private

  def calculate_total_cost
    self.total_cost = (input_cost || 0) + (output_cost || 0)
  end

  def set_environment
    self.environment ||= Rails.env
  end

  def check_usage_limits
    return unless expensive? || slow? || high_token_usage?

    Rails.logger.warn "High-cost API call: #{to_analytics_json.to_json}"

    # Could trigger alerts, send to monitoring, etc.
    ApiCallAlertJob.perform_later(self) if defined?(ApiCallAlertJob)
  end

  def broadcast_if_expensive
    return unless expensive?

    # Broadcast to monitoring dashboard
    ActionCable.server.broadcast(
      "api_monitoring",
      {
        event: "expensive_call",
        call: to_analytics_json
      }
    )
  end

  def alert_on_failure
    return unless failed?

    Rails.logger.error "API call failed: #{to_analytics_json.to_json}"

    # Could send to error tracking service
    Sentry.capture_message("API call failed", extra: to_analytics_json) if defined?(Sentry)
  end

  def extract_response_data(result)
    # Override in subclasses for provider-specific extraction
    case result
    when Hash
      result
    when OpenStruct
      result.to_h
    else
      result.try(:to_h) || {}
    end
  end

  def extract_error_details(error)
    details = {
      class: error.class.name,
      backtrace: error.backtrace&.first(5)
    }

    # Extract provider-specific error details
    if error.respond_to?(:response)
      details[:response] = error.response
    end

    if error.respond_to?(:http_status)
      details[:http_status] = error.http_status
    end

    details
  end

  def self.percentile(scope, column, percentile)
    values = scope.pluck(column).compact.sort
    return nil if values.empty?

    index = (percentile * (values.length - 1)).round
    values[index]
  end
end
