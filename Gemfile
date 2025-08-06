source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.0.2"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"
# Use Tailwind CSS [https://github.com/rails/tailwindcss-rails]
gem "tailwindcss-rails"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
# gem "image_processing", "~> 1.2"

# OpenAI integration - official OpenAI Ruby gem
gem "openai", "~> 0.16.0"

# Neo4j for knowledge graph
gem "neo4j-ruby-driver"
# gem "activegraph" # Not using ActiveGraph OGM, using direct driver instead

# CSV processing (required for Ruby 3.4+)
gem "csv"

# Colorized terminal output
gem "rainbow"

# Vector embeddings with pgvector
gem "neighbor"

# PostgreSQL full-text search
gem "pg_search"

# Background processing - using Solid Queue instead of Sidekiq

# File processing
gem "rubyzip"
gem "marcel" # MIME type detection
gem "pdf-reader"
gem "mini_magick" # For image processing
gem "ruby-vips" # For efficient image processing

# Text processing helpers
gem "unicode-display_width"
gem "fast_blank"

# API and serialization
gem "jsonapi-serializer"
gem "oj" # Fast JSON parsing

# Authentication and authorization
gem "devise"
gem "pundit"

# Environment management
gem "dotenv-rails"

# HTTP client
gem "faraday"
gem "faraday-retry"

# Caching enhancements
gem "redis", "~> 5.0"
gem "connection_pool"

# Monitoring and observability (to be added later)
# gem "opentelemetry-sdk"
# gem "opentelemetry-exporter-otlp"
# gem "opentelemetry-instrumentation-rails"

# Data validation
gem "dry-validation"
gem "dry-struct"

# AWS SDK for S3 (if not using MinIO)
gem "aws-sdk-s3"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false
  
  # Testing
  gem "rspec-rails"
  gem "factory_bot_rails"
  gem "faker"
  gem "shoulda-matchers"
  gem "database_cleaner-active_record"
  
  # Performance testing
  gem "benchmark-ips"
  gem "memory_profiler"
end

group :test do
  # System testing
  gem "capybara"
  gem "selenium-webdriver"
  
  # API testing
  gem "webmock"
  gem "vcr"
  
  # Code coverage
  gem "simplecov", require: false
  gem "simplecov-lcov", require: false
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"
end

gem "activegraph", "~> 11.4"
