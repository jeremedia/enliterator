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
# Tracks Anthropic (Claude) API calls with provider-specific pricing and features
class AnthropicApiCall < ApiCall
  # Anthropic pricing (August 2025 estimates - update with actual pricing)
  # Prices are per 1M tokens
  PRICING = {
    # Claude 3.5 family
    'claude-3.5-opus' => { input: 15.00, output: 75.00 },
    'claude-3.5-sonnet' => { input: 3.00, output: 15.00 },
    'claude-3.5-haiku' => { input: 0.25, output: 1.25 },
    
    # Claude 3 family
    'claude-3-opus-20240229' => { input: 15.00, output: 75.00 },
    'claude-3-sonnet-20240229' => { input: 3.00, output: 15.00 },
    'claude-3-haiku-20240307' => { input: 0.25, output: 1.25 },
    
    # Claude 2 family (legacy)
    'claude-2.1' => { input: 8.00, output: 24.00 },
    'claude-2.0' => { input: 8.00, output: 24.00 },
    'claude-instant-1.2' => { input: 0.80, output: 2.40 }
  }.freeze
  
  # Anthropic-specific rate limits
  RATE_LIMITS = {
    'claude-3.5-opus' => { rpm: 50, tpm: 100_000 },
    'claude-3.5-sonnet' => { rpm: 100, tpm: 200_000 },
    'claude-3.5-haiku' => { rpm: 200, tpm: 300_000 },
    'claude-3-opus-20240229' => { rpm: 50, tpm: 100_000 },
    'claude-3-sonnet-20240229' => { rpm: 100, tpm: 200_000 },
    'claude-3-haiku-20240307' => { rpm: 200, tpm: 300_000 }
  }.freeze
  
  # Context window sizes
  CONTEXT_WINDOWS = {
    'claude-3.5-opus' => 200_000,
    'claude-3.5-sonnet' => 200_000,
    'claude-3.5-haiku' => 200_000,
    'claude-3-opus-20240229' => 200_000,
    'claude-3-sonnet-20240229' => 200_000,
    'claude-3-haiku-20240307' => 200_000,
    'claude-2.1' => 200_000,
    'claude-2.0' => 100_000,
    'claude-instant-1.2' => 100_000
  }.freeze
  
  # Provider capabilities
  def self.supports_streaming?
    true
  end
  
  def self.supports_functions?
    true  # Via tool use
  end
  
  def self.supports_vision?
    true  # Claude 3+ models
  end
  
  def self.supports_batching?
    true
  end
  
  # Anthropic supports prompt caching
  def supports_caching?
    model_used&.start_with?('claude-3')
  end
  
  def calculate_costs!
    return unless model_used && prompt_tokens && completion_tokens
    
    pricing = PRICING[model_used]
    unless pricing
      Rails.logger.warn "No pricing found for Anthropic model: #{model_used}"
      return
    end
    
    # Base token costs
    base_input_cost = (prompt_tokens.to_f / 1_000_000) * pricing[:input]
    base_output_cost = (completion_tokens.to_f / 1_000_000) * pricing[:output]
    
    # Apply cache discount if applicable
    if cached_tokens && cached_tokens > 0
      # Cached tokens are 90% cheaper
      cache_discount = (cached_tokens.to_f / prompt_tokens) * 0.9
      self.input_cost = base_input_cost * (1 - cache_discount)
      
      # Store cache savings in metadata
      self.metadata['cache_savings'] = base_input_cost * cache_discount
    else
      self.input_cost = base_input_cost
    end
    
    self.output_cost = base_output_cost
  end
  
  def extract_usage_data(result)
    if result.respond_to?(:usage)
      # Anthropic uses different field names
      self.prompt_tokens = result.usage.input_tokens
      self.completion_tokens = result.usage.output_tokens
      self.total_tokens = prompt_tokens + completion_tokens
      
      # Cache-specific fields
      if result.usage.respond_to?(:cache_creation_input_tokens)
        self.metadata['cache_creation_tokens'] = result.usage.cache_creation_input_tokens
      end
      
      if result.usage.respond_to?(:cache_read_input_tokens)
        self.cached_tokens = result.usage.cache_read_input_tokens
      end
    elsif result.is_a?(Hash) && result['usage']
      usage = result['usage']
      self.prompt_tokens = usage['input_tokens']
      self.completion_tokens = usage['output_tokens']
      self.total_tokens = prompt_tokens + completion_tokens
      self.cached_tokens = usage['cache_read_input_tokens']
    end
    
    # Store the actual model used
    if result.respond_to?(:model)
      self.model_version = result.model
    end
    
    # Store stop reason (important for Anthropic)
    if result.respond_to?(:stop_reason)
      self.metadata['stop_reason'] = result.stop_reason
    end
  end
  
  # Check if we're within context window
  def within_context_window?
    return true unless model_used && total_tokens
    
    max_tokens = CONTEXT_WINDOWS[model_used]
    return true unless max_tokens
    
    total_tokens <= max_tokens
  end
  
  # Anthropic-specific error handling
  def extract_error_details(error)
    details = super
    
    # Extract Anthropic-specific error information
    if error.respond_to?(:response) && error.response.is_a?(Hash)
      details[:anthropic_error] = {
        type: error.response['error']&.dig('type'),
        message: error.response['error']&.dig('message')
      }
    end
    
    # Handle specific Anthropic errors
    case error.message
    when /context_length_exceeded/
      details[:exceeded_tokens] = total_tokens - (CONTEXT_WINDOWS[model_used] || 0)
    when /rate_limit/
      details[:retry_after] = error.response&.dig('retry_after')
    end
    
    details
  end
  
  # Anthropic's message format converter
  def self.convert_openai_messages_to_anthropic(openai_messages)
    system_message = nil
    messages = []
    
    openai_messages.each do |msg|
      case msg[:role]
      when 'system'
        system_message = msg[:content]
      when 'user'
        messages << { role: 'user', content: msg[:content] }
      when 'assistant'
        messages << { role: 'assistant', content: msg[:content] }
      end
    end
    
    {
      system: system_message,
      messages: messages
    }
  end
  
  # Check approaching rate limits
  def approaching_rate_limit?
    return false unless model_used
    
    limits = RATE_LIMITS[model_used]
    return false unless limits
    
    # Check requests in the last minute
    recent_calls = self.class
      .where(model_used: model_used)
      .where('created_at > ?', 1.minute.ago)
    
    rpm_usage = recent_calls.count
    tpm_usage = recent_calls.sum(:total_tokens)
    
    rpm_usage >= (limits[:rpm] * 0.8) || tpm_usage >= (limits[:tpm] * 0.8)
  end
  
  # Cache effectiveness metrics
  def cache_hit_rate
    return 0 unless cached_tokens && prompt_tokens && prompt_tokens > 0
    
    (cached_tokens.to_f / prompt_tokens * 100).round(2)
  end
  
  def cache_savings_percentage
    return 0 unless metadata['cache_savings'] && input_cost
    
    total_potential_cost = input_cost + (metadata['cache_savings'] || 0)
    return 0 if total_potential_cost == 0
    
    (metadata['cache_savings'] / total_potential_cost * 100).round(2)
  end
  
  # Anthropic-specific analytics
  def self.cache_analytics(period = :today)
    scope = period == :today ? today : where(created_at: period)
    
    {
      total_calls: scope.count,
      calls_with_cache: scope.where('cached_tokens > 0').count,
      cache_hit_rate: scope.average('cached_tokens::float / NULLIF(prompt_tokens, 0) * 100').to_f.round(2),
      total_cache_savings: scope.sum("metadata->>'cache_savings'").to_f.round(2),
      avg_cache_tokens: scope.average(:cached_tokens).to_i,
      top_cached_models: scope
        .where('cached_tokens > 0')
        .group(:model_used)
        .sum(:cached_tokens)
        .sort_by { |_, v| -v }
    }
  end
end
