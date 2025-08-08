# frozen_string_literal: true

require 'test_helper'

class OpenaiApiCallTest < ActiveSupport::TestCase
  def setup
    @api_call = OpenaiApiCall.new(
      service_name: 'TestService',
      endpoint: 'responses.create',
      model_used: 'gpt-4.1',
      status: 'pending'
    )
  end
  
  test "should support OpenAI-specific features" do
    assert OpenaiApiCall.supports_streaming?
    assert OpenaiApiCall.supports_functions?
    assert OpenaiApiCall.supports_vision?
    assert OpenaiApiCall.supports_batching?
  end
  
  test "should calculate text model costs correctly" do
    @api_call.model_used = 'gpt-4.1'
    @api_call.prompt_tokens = 1000
    @api_call.completion_tokens = 500
    @api_call.calculate_costs!
    
    # gpt-4.1: $2.50 per 1M input, $10 per 1M output
    expected_input = (1000.0 / 1_000_000) * 2.50
    expected_output = (500.0 / 1_000_000) * 10.00
    
    assert_in_delta expected_input, @api_call.input_cost, 0.00001
    assert_in_delta expected_output, @api_call.output_cost, 0.00001
    assert_in_delta expected_input + expected_output, @api_call.total_cost, 0.00001
  end
  
  test "should calculate mini model costs correctly" do
    @api_call.model_used = 'gpt-4.1-mini'
    @api_call.prompt_tokens = 10_000
    @api_call.completion_tokens = 5_000
    @api_call.calculate_costs!
    
    # gpt-4.1-mini: $0.15 per 1M input, $0.60 per 1M output
    expected_input = (10_000.0 / 1_000_000) * 0.15
    expected_output = (5_000.0 / 1_000_000) * 0.60
    
    assert_in_delta expected_input, @api_call.input_cost, 0.00001
    assert_in_delta expected_output, @api_call.output_cost, 0.00001
  end
  
  test "should calculate image generation costs for gpt-image-1" do
    @api_call.endpoint = 'images.generate'
    @api_call.model_used = 'gpt-image-1'
    @api_call.image_size = '1024x1024'
    @api_call.image_quality = 'high'
    @api_call.image_count = 2
    @api_call.calculate_costs!
    
    # gpt-image-1 1024x1024 high: $0.08 per image
    expected_cost = 0.08 * 2
    
    assert_equal 0, @api_call.input_cost
    assert_equal expected_cost, @api_call.output_cost
    assert_equal expected_cost, @api_call.total_cost
  end
  
  test "should calculate image generation costs for dall-e-3" do
    @api_call.endpoint = 'images.generate'
    @api_call.model_used = 'dall-e-3'
    @api_call.image_size = '1792x1024'
    @api_call.image_quality = 'hd'
    @api_call.image_count = 1
    @api_call.calculate_costs!
    
    # dall-e-3 1792x1024 hd: $0.12 per image
    expected_cost = 0.12
    
    assert_equal 0, @api_call.input_cost
    assert_equal expected_cost, @api_call.output_cost
    assert_equal expected_cost, @api_call.total_cost
  end
  
  test "should calculate embedding costs" do
    @api_call.endpoint = 'embeddings.create'
    @api_call.model_used = 'text-embedding-3-small'
    @api_call.total_tokens = 5000
    @api_call.calculate_costs!
    
    # text-embedding-3-small: $0.02 per 1M tokens
    expected_cost = (5000.0 / 1_000_000) * 0.02
    
    assert_equal expected_cost, @api_call.input_cost
    assert_equal 0, @api_call.output_cost
    assert_equal expected_cost, @api_call.total_cost
  end
  
  test "should extract text usage data from response" do
    response = OpenStruct.new(
      usage: OpenStruct.new(
        prompt_tokens: 100,
        completion_tokens: 50,
        total_tokens: 150
      ),
      model: 'gpt-4.1-2025-04-14'
    )
    
    @api_call.extract_usage_data(response)
    
    assert_equal 100, @api_call.prompt_tokens
    assert_equal 50, @api_call.completion_tokens
    assert_equal 150, @api_call.total_tokens
    assert_equal 'gpt-4.1-2025-04-14', @api_call.model_version
  end
  
  test "should extract image usage data from response" do
    @api_call.endpoint = 'images.generate'
    
    response = OpenStruct.new(
      data: [
        OpenStruct.new(
          url: 'https://example.com/image1.png',
          b64_json: nil,
          revised_prompt: 'Enhanced prompt'
        ),
        OpenStruct.new(
          url: 'https://example.com/image2.png',
          b64_json: nil,
          revised_prompt: nil
        )
      ]
    )
    
    @api_call.extract_usage_data(response)
    
    assert_equal 2, @api_call.image_count
    assert_equal 2, @api_call.response_data[:images].size
    assert_equal 'https://example.com/image1.png', @api_call.response_data[:images][0][:url]
    assert_equal 'Enhanced prompt', @api_call.response_data[:images][0][:revised_prompt]
  end
  
  test "should detect approaching rate limits" do
    # Create recent calls for the same model
    4.times do
      OpenaiApiCall.create!(
        service_name: 'TestService',
        endpoint: 'test',
        model_used: 'dall-e-3',
        status: 'success'
      )
    end
    
    @api_call.model_used = 'dall-e-3'
    
    # dall-e-3 has limit of 5 rpm, 4 calls = 80% = approaching
    assert @api_call.approaching_rate_limit?
    
    @api_call.model_used = 'gpt-4.1'
    # gpt-4.1 has limit of 500 rpm, 4 calls = not approaching
    assert_not @api_call.approaching_rate_limit?
  end
  
  test "should handle unknown model gracefully" do
    @api_call.model_used = 'unknown-model'
    @api_call.prompt_tokens = 100
    @api_call.completion_tokens = 50
    
    # Should not raise error
    assert_nothing_raised do
      @api_call.calculate_costs!
    end
    
    # Costs should remain nil or 0
    assert_nil @api_call.input_cost
    assert_nil @api_call.output_cost
  end
  
  test "should extract OpenAI-specific error details" do
    error = OpenStruct.new(
      message: "Rate limit exceeded",
      response: {
        'error' => {
          'type' => 'rate_limit_error',
          'message' => 'You have exceeded your rate limit',
          'param' => 'messages',
          'code' => 'rate_limit_exceeded'
        }
      }
    )
    
    details = @api_call.extract_error_details(error)
    
    assert_equal 'OpenStruct', details[:class]
    assert_not_nil details[:openai_error]
    assert_equal 'rate_limit_error', details[:openai_error][:type]
    assert_equal 'You have exceeded your rate limit', details[:openai_error][:message]
    assert_equal 'messages', details[:openai_error][:param]
    assert_equal 'rate_limit_exceeded', details[:openai_error][:code]
  end
  
  test "should handle model version in pricing" do
    @api_call.model_used = 'gpt-4.1-2025-04-14'  # Versioned model name
    @api_call.prompt_tokens = 1000
    @api_call.completion_tokens = 500
    @api_call.calculate_costs!
    
    # Should use base model pricing (gpt-4.1)
    expected_input = (1000.0 / 1_000_000) * 2.50
    expected_output = (500.0 / 1_000_000) * 10.00
    
    assert_in_delta expected_input, @api_call.input_cost, 0.00001
    assert_in_delta expected_output, @api_call.output_cost, 0.00001
  end
end