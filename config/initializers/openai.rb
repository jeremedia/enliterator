# frozen_string_literal: true

require "openai"

# Create global OpenAI client instance using the official openai-ruby gem
OPENAI = OpenAI::Client.new(
  api_key: ENV.fetch("OPENAI_API_KEY", nil),
  timeout: 120, # 2 minutes
  max_retries: 2 # Default retry attempts
)

# Validate configuration in development/test
if Rails.env.development? || Rails.env.test?
  if ENV["OPENAI_API_KEY"].blank?
    Rails.logger.warn "OPENAI_API_KEY is not set. OpenAI features will not work."
  end
end

# OpenAI model configuration
Rails.application.config.openai = {
  # Models that support Structured Outputs (Responses API)
  extraction_model: ENV.fetch("OPENAI_MODEL"),
  answer_model: ENV.fetch("OPENAI_MODEL_ANSWER"),
  fine_tune_base: ENV.fetch("OPENAI_FT_BASE"),
  fine_tune_model: ENV.fetch("OPENAI_FT_MODEL", nil),
  
  # Temperature settings - MUST be 0 for extraction
  temperature: {
    extraction: 0.0,  # Required for deterministic structured outputs
    answer: 0.7,
    routing: 0.0
  },
  
  # Structured output settings
  structured_outputs: {
    strict: true,  # Enforce schema compliance
    supported_models: ["gpt-4.1", "gpt-4.1-mini", "gpt-4.1-nano"]
  }
}

# Helper method to ensure model supports structured outputs
def structured_output_model?(model)
  Rails.application.config.openai[:structured_outputs][:supported_models].include?(model)
end