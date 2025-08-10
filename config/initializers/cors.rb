# frozen_string_literal: true

# CORS configuration for MCP Server
#
# Server-Sent Events (SSE) requires specific CORS configuration
# to work properly with AI clients like ChatGPT and Claude
#
# In production, replace '*' with specific allowed origins:
# - https://chat.openai.com (for ChatGPT)
# - Your application domain

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    # In development, allow all origins
    # In production, specify exact domains
    origins '*'
    
    # MCP endpoints need special CORS handling for SSE
    resource '/api/v1/mcp/*',
             headers: :any,
             methods: [:get, :post, :options],
             expose: ['Content-Type', 'X-Request-Id', 'Cache-Control'],
             credentials: false  # Set to true if using cookies
  end
  
  # Allow other API endpoints if needed
  allow do
    origins '*'
    resource '/api/*',
             headers: :any,
             methods: [:get, :post, :put, :patch, :delete, :options, :head]
  end
end