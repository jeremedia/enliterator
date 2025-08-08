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
class OpenaiApiCall < ApiCall
  # OpenAI-specific pricing (August 2025 - gpt-4.1 family)
  # Prices are per 1M tokens for text models, per image for image models
  PRICING = {
    # GPT-4.1 family (per 1M tokens)
    'gpt-4.1' => { input: 2.50, output: 10.00 },
    'gpt-4.1-2025-04-14' => { input: 2.50, output: 10.00 },
    'gpt-4.1-mini' => { input: 0.15, output: 0.60 },
    'gpt-4.1-mini-2025-04-14' => { input: 0.15, output: 0.60 },
    'gpt-4.1-nano' => { input: 0.05, output: 0.20 },
    'gpt-4.1-nano-2025-04-14' => { input: 0.05, output: 0.20 },
    
    # Legacy models (if still in use - per 1M tokens)
    'gpt-4o' => { input: 5.00, output: 15.00 },
    'gpt-4o-2024-08-06' => { input: 5.00, output: 15.00 },
    'gpt-4o-mini' => { input: 0.30, output: 1.20 },
    'gpt-3.5-turbo' => { input: 0.50, output: 1.50 },
    
    # Image models (per image)
    'gpt-image-1' => {
      '1024x1024' => { high: 0.08, medium: 0.06, low: 0.04 },
      '1024x1536' => { high: 0.10, medium: 0.08, low: 0.06 },
      '1536x1024' => { high: 0.10, medium: 0.08, low: 0.06 },
      '4096x4096' => { high: 0.16, medium: 0.12, low: 0.08 }
    },
    'dall-e-3' => {
      '1024x1024' => { hd: 0.08, standard: 0.04 },
      '1792x1024' => { hd: 0.12, standard: 0.08 },
      '1024x1792' => { hd: 0.12, standard: 0.08 }
    },
    'dall-e-2' => {
      '1024x1024' => 0.02,
      '512x512' => 0.018,
      '256x256' => 0.016
    },
    
    # Embeddings (per 1M tokens)
    'text-embedding-3-small' => 0.02,
    'text-embedding-3-large' => 0.13,
    'text-embedding-ada-002' => 0.10,
    
    # Audio models
    'whisper-1' => 0.006,  # per minute
    'tts-1' => 0.015,      # per 1M characters
    'tts-1-hd' => 0.030    # per 1M characters
  }.freeze
  
  # Rate limits by model tier (requests per minute)
  RATE_LIMITS = {
    'gpt-4.1' => { rpm: 500, tpm: 150_000 },
    'gpt-4.1-mini' => { rpm: 3_500, tpm: 200_000 },
    'gpt-4.1-nano' => { rpm: 5_000, tpm: 300_000 },
    'gpt-image-1' => { rpm: 50, images_per_minute: 100 },
    'dall-e-3' => { rpm: 5, images_per_minute: 7 },
    'dall-e-2' => { rpm: 50, images_per_minute: 100 }
  }.freeze
  
  # Provider capabilities
  def self.supports_streaming?
    true
  end
  
  def self.supports_functions?
    true
  end
  
  def self.supports_vision?
    true
  end
  
  def self.supports_batching?
    true
  end
  
  def calculate_costs!
    case endpoint
    when /image/
      calculate_image_costs!
    when /embedding/
      calculate_embedding_costs!
    when /audio|whisper|tts/
      calculate_audio_costs!
    else
      calculate_text_costs!
    end
  end
  
  def extract_usage_data(result)
    case endpoint
    when 'responses.create', 'chat.completions.create'
      extract_text_usage(result)
    when 'images.generate', 'images.edit', 'images.variations'
      extract_image_usage(result)
    when 'embeddings.create'
      extract_embedding_usage(result)
    when 'audio.transcriptions.create', 'audio.translations.create'
      extract_audio_usage(result)
    else
      extract_generic_usage(result)
    end
  end
  
  # Check if we're approaching rate limits
  def approaching_rate_limit?
    return false unless model_used
    
    limits = RATE_LIMITS[model_used]
    return false unless limits
    
    # Check requests in the last minute
    recent_calls = self.class
      .where(model_used: model_used)
      .where('created_at > ?', 1.minute.ago)
      .count
    
    recent_calls >= (limits[:rpm] * 0.8)  # Alert at 80% of limit
  end
  
  # OpenAI-specific error handling
  def extract_error_details(error)
    details = super
    
    # Extract OpenAI-specific error information
    if error.respond_to?(:response) && error.response.is_a?(Hash)
      details[:openai_error] = {
        type: error.response.dig('error', 'type'),
        message: error.response.dig('error', 'message'),
        param: error.response.dig('error', 'param'),
        code: error.response.dig('error', 'code')
      }
    end
    
    details
  end
  
  private
  
  def calculate_text_costs!
    return unless model_used && prompt_tokens && completion_tokens
    
    pricing = PRICING[model_used] || PRICING[model_used.split('-').first]
    unless pricing
      Rails.logger.warn "No pricing found for model: #{model_used}"
      return
    end
    
    # Convert from per 1M tokens to actual cost
    self.input_cost = (prompt_tokens.to_f / 1_000_000) * pricing[:input]
    self.output_cost = (completion_tokens.to_f / 1_000_000) * pricing[:output]
  end
  
  def calculate_image_costs!
    return unless model_used && image_size
    
    quality = image_quality || 'standard'
    count = image_count || 1
    
    price = case model_used
            when 'gpt-image-1', 'dall-e-3'
              pricing = PRICING[model_used][image_size]
              pricing.is_a?(Hash) ? pricing[quality.to_sym] : pricing
            when 'dall-e-2'
              PRICING[model_used][image_size]
            else
              Rails.logger.warn "Unknown image model: #{model_used}"
              0
            end
    
    self.total_cost = (price || 0) * count
    self.input_cost = 0
    self.output_cost = self.total_cost
  end
  
  def calculate_embedding_costs!
    return unless model_used && total_tokens
    
    price_per_million = PRICING[model_used]
    unless price_per_million
      Rails.logger.warn "No pricing found for embedding model: #{model_used}"
      return
    end
    
    self.total_cost = (total_tokens.to_f / 1_000_000) * price_per_million
    self.input_cost = self.total_cost
    self.output_cost = 0
  end
  
  def calculate_audio_costs!
    case model_used
    when 'whisper-1'
      # Charged per minute of audio
      duration_minutes = (audio_duration || 0) / 60.0
      self.total_cost = duration_minutes * PRICING['whisper-1']
      self.input_cost = self.total_cost
      self.output_cost = 0
    when /tts/
      # Charged per 1M characters
      characters = response_data['characters'] || prompt_tokens || 0
      price_per_million = PRICING[model_used] || 0
      self.total_cost = (characters.to_f / 1_000_000) * price_per_million
      self.input_cost = 0
      self.output_cost = self.total_cost
    end
  end
  
  def extract_text_usage(result)
    if result.respond_to?(:usage)
      usage = result.usage
      
      # Handle both old and new OpenAI gem response structures
      if usage.respond_to?(:prompt_tokens)
        # Direct method access (new gem structure)
        self.prompt_tokens = usage.prompt_tokens
        self.completion_tokens = usage.completion_tokens
        self.total_tokens = usage.total_tokens
        
        # GPT-4.1 with reasoning
        if usage.respond_to?(:reasoning_tokens)
          self.reasoning_tokens = usage.reasoning_tokens
        end
      elsif usage.is_a?(Hash)
        # Hash-like access (old structure)
        self.prompt_tokens = usage['prompt_tokens']
        self.completion_tokens = usage['completion_tokens']
        self.total_tokens = usage['total_tokens']
        self.reasoning_tokens = usage['reasoning_tokens']
      end
    elsif result.is_a?(Hash) && result['usage']
      usage = result['usage']
      self.prompt_tokens = usage['prompt_tokens']
      self.completion_tokens = usage['completion_tokens']
      self.total_tokens = usage['total_tokens']
      self.reasoning_tokens = usage['reasoning_tokens']
    end
    
    # Store the model actually used (important for fallbacks)
    if result.respond_to?(:model)
      self.model_version = result.model
    end
  end
  
  def extract_image_usage(result)
    if result.respond_to?(:data)
      self.image_count = result.data.size
      
      # Store image URLs or base64 data
      self.response_data = {
        images: result.data.map { |img| 
          {
            url: img.url,
            b64_json: img.b64_json.present? ? '[base64_data]' : nil,
            revised_prompt: img.revised_prompt
          }.compact
        }
      }
    end
  end
  
  def extract_embedding_usage(result)
    if result.respond_to?(:usage)
      usage = result.usage
      
      # Handle both old and new OpenAI gem response structures
      if usage.respond_to?(:prompt_tokens)
        # Direct method access (new gem structure)
        self.prompt_tokens = usage.prompt_tokens
        self.total_tokens = usage.total_tokens
      elsif usage.is_a?(Hash)
        # Hash-like access (old structure)
        self.prompt_tokens = usage['prompt_tokens']
        self.total_tokens = usage['total_tokens']
      end
      
      self.completion_tokens = 0  # Embeddings have no completion tokens
    end
    
    # Store embedding dimensions
    if result.respond_to?(:data) && result.data.first
      self.metadata['embedding_dimensions'] = result.data.first.embedding.size
    end
  end
  
  def extract_audio_usage(result)
    if result.respond_to?(:duration)
      self.audio_duration = result.duration
    end
    
    if result.respond_to?(:text)
      self.metadata['transcription_length'] = result.text.length
    end
  end
  
  def extract_generic_usage(result)
    # Fallback for any new endpoints
    if result.respond_to?(:usage)
      self.prompt_tokens = result.usage.try(:prompt_tokens)
      self.completion_tokens = result.usage.try(:completion_tokens)
      self.total_tokens = result.usage.try(:total_tokens)
    end
  end
end
