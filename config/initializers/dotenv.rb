# frozen_string_literal: true

# Load environment variables from .env file in development and test
if Rails.env.development? || Rails.env.test?
  require "dotenv"
  
  # Load .env.local first (for local overrides)
  Dotenv.load(".env.local") if File.exist?(".env.local")
  
  # Then load .env
  Dotenv.load(".env") if File.exist?(".env")
  
  # Load test-specific env vars
  Dotenv.load(".env.test") if Rails.env.test? && File.exist?(".env.test")
end