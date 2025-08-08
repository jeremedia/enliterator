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
require 'test_helper'

class ApiCallTest < ActiveSupport::TestCase
  def setup
    @api_call = OpenaiApiCall.new(
      service_name: 'TestService',
      endpoint: 'test.endpoint',
      model_used: 'gpt-4.1',
      status: 'pending'
    )
  end
  
  test "should be valid with required attributes" do
    assert @api_call.valid?
  end
  
  test "should require type for STI" do
    api_call = ApiCall.new(
      service_name: 'TestService',
      endpoint: 'test.endpoint'
    )
    assert_not api_call.valid?
    assert_includes api_call.errors[:type], "can't be blank"
  end
  
  test "should require service_name" do
    @api_call.service_name = nil
    assert_not @api_call.valid?
    assert_includes @api_call.errors[:service_name], "can't be blank"
  end
  
  test "should require endpoint" do
    @api_call.endpoint = nil
    assert_not @api_call.valid?
    assert_includes @api_call.errors[:endpoint], "can't be blank"
  end
  
  test "should calculate total cost" do
    @api_call.input_cost = 0.05
    @api_call.output_cost = 0.10
    @api_call.save!
    
    assert_equal 0.15, @api_call.total_cost
  end
  
  test "should set environment on save" do
    @api_call.save!
    assert_equal Rails.env, @api_call.environment
  end
  
  test "should track execution successfully" do
    @api_call.save!
    
    mock_response = OpenStruct.new(
      usage: OpenStruct.new(
        prompt_tokens: 100,
        completion_tokens: 50,
        total_tokens: 150
      ),
      model: 'gpt-4.1'
    )
    
    result = @api_call.track_execution do |call|
      mock_response
    end
    
    assert_equal 'success', @api_call.status
    assert_equal 100, @api_call.prompt_tokens
    assert_equal 50, @api_call.completion_tokens
    assert_equal 150, @api_call.total_tokens
    assert_not_nil @api_call.response_time_ms
    assert_equal mock_response, result
  end
  
  test "should track execution failure" do
    @api_call.save!
    
    assert_raises(StandardError) do
      @api_call.track_execution do |call|
        raise StandardError, "API Error"
      end
    end
    
    assert_equal 'failed', @api_call.status
    assert_equal "API Error", @api_call.error_message
    assert_equal "StandardError", @api_call.error_code
    assert_not_nil @api_call.response_time_ms
  end
  
  test "should detect rate limit errors" do
    @api_call.save!
    
    assert_raises(OpenAI::RateLimitError) do
      @api_call.track_execution do |call|
        raise OpenAI::RateLimitError, "Rate limit exceeded"
      end
    end
    
    assert_equal 'rate_limited', @api_call.status
    assert_equal "Rate limit exceeded", @api_call.error_message
  end
  
  test "should detect timeout errors" do
    @api_call.save!
    
    assert_raises(Net::ReadTimeout) do
      @api_call.track_execution do |call|
        raise Net::ReadTimeout, "Connection timed out"
      end
    end
    
    assert_equal 'timeout', @api_call.status
    assert_equal "Connection timed out", @api_call.error_message
  end
  
  test "should calculate cost per 1k tokens" do
    @api_call.total_cost = 0.15
    @api_call.total_tokens = 3000
    
    assert_equal 50.0, @api_call.cost_per_1k_tokens
  end
  
  test "should handle zero tokens in cost calculation" do
    @api_call.total_cost = 0.15
    @api_call.total_tokens = 0
    
    assert_equal 0, @api_call.cost_per_1k_tokens
  end
  
  test "should identify expensive calls" do
    @api_call.total_cost = 0.05
    assert_not @api_call.expensive?
    
    @api_call.total_cost = 0.15
    assert @api_call.expensive?
  end
  
  test "should identify slow calls" do
    @api_call.response_time_ms = 3000
    assert_not @api_call.slow?
    
    @api_call.response_time_ms = 6000
    assert @api_call.slow?
  end
  
  test "should identify high token usage" do
    @api_call.total_tokens = 3000
    assert_not @api_call.high_token_usage?
    
    @api_call.total_tokens = 5000
    assert @api_call.high_token_usage?
  end
  
  test "should generate cache key for request" do
    @api_call.endpoint = 'test.endpoint'
    @api_call.model_used = 'gpt-4.1'
    @api_call.request_params = { prompt: 'test' }
    
    key1 = @api_call.cache_key_for_request
    assert_not_nil key1
    
    # Same params should generate same key
    @api_call2 = @api_call.dup
    key2 = @api_call2.cache_key_for_request
    assert_equal key1, key2
    
    # Different params should generate different key
    @api_call.request_params = { prompt: 'different' }
    key3 = @api_call.cache_key_for_request
    assert_not_equal key1, key3
  end
  
  test "should find cached response" do
    @api_call.endpoint = 'test.endpoint'
    @api_call.model_used = 'gpt-4.1'
    @api_call.cache_key = Digest::SHA256.hexdigest(['test.endpoint', 'gpt-4.1', {prompt: 'test'}.to_json].join(':'))
    @api_call.status = 'success'
    @api_call.save!
    
    found = ApiCall.find_cached_response(
      endpoint: 'test.endpoint',
      model: 'gpt-4.1',
      params: { prompt: 'test' }
    )
    
    assert_equal @api_call, found
  end
  
  test "should not find expired cached response" do
    @api_call.endpoint = 'test.endpoint'
    @api_call.model_used = 'gpt-4.1'
    @api_call.cache_key = Digest::SHA256.hexdigest(['test.endpoint', 'gpt-4.1', {prompt: 'test'}.to_json].join(':'))
    @api_call.status = 'success'
    @api_call.created_at = 2.hours.ago
    @api_call.save!
    
    found = ApiCall.find_cached_response(
      endpoint: 'test.endpoint',
      model: 'gpt-4.1',
      params: { prompt: 'test' }
    )
    
    assert_nil found
  end
  
  test "should generate analytics json" do
    @api_call.prompt_tokens = 100
    @api_call.completion_tokens = 50
    @api_call.total_tokens = 150
    @api_call.input_cost = 0.05
    @api_call.output_cost = 0.10
    @api_call.total_cost = 0.15
    @api_call.response_time_ms = 1500
    @api_call.save!
    
    json = @api_call.to_analytics_json
    
    assert_equal @api_call.id, json[:id]
    assert_equal 'Openai', json[:provider]
    assert_equal 'TestService', json[:service]
    assert_equal 'test.endpoint', json[:endpoint]
    assert_equal 'gpt-4.1', json[:model]
    assert_equal 100, json[:tokens][:prompt]
    assert_equal 50, json[:tokens][:completion]
    assert_equal 150, json[:tokens][:total]
    assert_equal 0.05, json[:cost][:input]
    assert_equal 0.10, json[:cost][:output]
    assert_equal 0.15, json[:cost][:total]
    assert_equal 1500, json[:performance][:response_time_ms]
  end
  
  test "should calculate usage summary" do
    # Create some test data
    OpenaiApiCall.create!(
      service_name: 'Service1',
      endpoint: 'endpoint1',
      model_used: 'gpt-4.1',
      status: 'success',
      total_cost: 0.10,
      total_tokens: 100
    )
    
    OpenaiApiCall.create!(
      service_name: 'Service2',
      endpoint: 'endpoint2',
      model_used: 'gpt-4.1-mini',
      status: 'failed',
      total_cost: 0.05,
      total_tokens: 50,
      error_code: 'timeout'
    )
    
    summary = ApiCall.usage_summary(:today)
    
    assert_not_nil summary[:by_provider]
    assert_not_nil summary[:by_model]
    assert_not_nil summary[:by_service]
    assert_not_nil summary[:by_status]
    assert_not_nil summary[:total]
  end
  
  test "should calculate cost breakdown" do
    # Create test data
    OpenaiApiCall.create!(
      service_name: 'Service1',
      endpoint: 'endpoint1',
      model_used: 'gpt-4.1',
      status: 'success',
      total_cost: 0.10,
      total_tokens: 100
    )
    
    breakdown = ApiCall.cost_breakdown(:today)
    
    assert_not_nil breakdown[:total_cost]
    assert_not_nil breakdown[:by_provider]
    assert_not_nil breakdown[:by_model]
    assert_not_nil breakdown[:by_service]
    assert_not_nil breakdown[:by_day]
    assert_not_nil breakdown[:expensive_calls]
  end
  
  test "should calculate performance metrics" do
    # Create test data with various response times
    [100, 200, 300, 400, 500, 1000, 2000, 3000, 4000, 5000].each do |ms|
      OpenaiApiCall.create!(
        service_name: 'TestService',
        endpoint: 'test',
        model_used: 'gpt-4.1',
        status: 'success',
        response_time_ms: ms
      )
    end
    
    metrics = ApiCall.performance_metrics(:today)
    
    assert_not_nil metrics[:avg_response_time]
    assert_not_nil metrics[:median_response_time]
    assert_not_nil metrics[:p95_response_time]
    assert_not_nil metrics[:p99_response_time]
    assert metrics[:p95_response_time] >= metrics[:median_response_time]
    assert metrics[:p99_response_time] >= metrics[:p95_response_time]
  end
end
