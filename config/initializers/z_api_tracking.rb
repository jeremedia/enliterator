# frozen_string_literal: true

# Initialize API tracking system
# This must run AFTER openai.rb initializer (alphabetically later)

# Ensure the ApiTracking module and adapters are loaded
Rails.application.config.after_initialize do
  if defined?(OPENAI)
    # Store the original client
    ORIGINAL_OPENAI = OPENAI
    
    # Replace with tracked version
    silence_warnings do
      # Create tracked wrapper for OpenAI
      tracked_client = ApiTracking::TrackedApiClient.new(
        provider: 'openai',
        client: ORIGINAL_OPENAI,
        cache_enabled: Rails.env.production? || Rails.env.development?
      )
      
      # Replace the constant
      Object.const_set(:OPENAI, tracked_client)
    end
    
    Rails.logger.info "[ApiTracking] OpenAI client wrapped with tracking"
  end

  # Future: When Anthropic is added
  # if defined?(ANTHROPIC)
  #   ORIGINAL_ANTHROPIC = ANTHROPIC
  #   silence_warnings do
  #     Object.const_set(:ANTHROPIC, ApiTracking::TrackedApiClient.new(
  #       provider: 'anthropic',
  #       client: ORIGINAL_ANTHROPIC,
  #       cache_enabled: true
  #     ))
  #   end
  # end

  # Future: When Ollama is added
  # if defined?(OLLAMA)
  #   ORIGINAL_OLLAMA = OLLAMA
  #   silence_warnings do
  #     Object.const_set(:OLLAMA, ApiTracking::TrackedApiClient.new(
  #       provider: 'ollama',
  #       client: ORIGINAL_OLLAMA,
  #       cache_enabled: false  # Local models don't need caching
  #     ))
  #   end
  # end

  Rails.logger.info "[ApiTracking] API tracking system initialized"
end

# Configuration for API tracking
Rails.application.config.api_tracking = {
  # Enable/disable tracking globally
  enabled: true,
  
  # Enable/disable response caching
  cache_enabled: Rails.env.production? || Rails.env.development?,
  
  # Cache durations for different endpoint types
  cache_durations: {
    embeddings: 1.week,
    models: 1.day,
    chat: 1.hour,
    default: 30.minutes
  },
  
  # Providers to track
  providers: %w[openai anthropic ollama],
  
  # Endpoints to exclude from tracking (regex patterns)
  excluded_endpoints: [],
  
  # Store complete responses
  store_full_response: true,
  
  # Maximum response size to store (in bytes)
  max_response_size: 10.megabytes
}