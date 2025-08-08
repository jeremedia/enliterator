class CreateApiCalls < ActiveRecord::Migration[8.0]
  def change
    create_table :api_calls do |t|
      # STI discriminator
      t.string :type, null: false  # OpenaiApiCall, AnthropicApiCall, OllamaApiCall, etc.
      
      # Common fields for all providers
      t.string :service_name, null: false      # Which service made the call
      t.string :endpoint, null: false          # API endpoint/method
      t.string :model_used                     # Model name
      t.string :model_version                  # Specific version if tracked
      
      # Request/Response (structure varies by provider)
      t.jsonb :request_params, default: {}
      t.jsonb :response_data, default: {}
      t.jsonb :response_headers, default: {}   # Rate limits, request IDs
      
      # Token usage (not all providers use all fields)
      t.integer :prompt_tokens                 # Input tokens
      t.integer :completion_tokens             # Output tokens  
      t.integer :total_tokens                  # Total tokens
      t.integer :cached_tokens                 # For providers with caching (Anthropic)
      t.integer :reasoning_tokens              # For models with reasoning (o1)
      
      # Image generation specific
      t.integer :image_count                   # Number of images
      t.string :image_size                     # Resolution
      t.string :image_quality                  # Quality tier
      
      # Audio generation specific
      t.float :audio_duration                  # Duration in seconds
      t.string :voice_id                       # Voice model used
      
      # Cost tracking
      t.decimal :input_cost, precision: 12, scale: 8
      t.decimal :output_cost, precision: 12, scale: 8
      t.decimal :total_cost, precision: 12, scale: 8
      t.string :currency, default: 'USD'
      
      # Performance metrics
      t.float :response_time_ms               # API response time
      t.float :processing_time_ms             # Local processing time
      t.integer :retry_count, default: 0
      t.float :queue_time_ms                  # Time spent in queue (if applicable)
      
      # Status and errors
      t.string :status, null: false, default: 'pending'
      t.string :error_code
      t.text :error_message
      t.jsonb :error_details, default: {}
      
      # Tracking and context
      t.references :trackable, polymorphic: true  # Link to IngestItem, Message, etc.
      t.references :user                          # Who triggered this
      t.string :request_id                        # Provider's request ID
      t.string :batch_id                          # For batch API calls
      t.string :response_cache_key                # For response caching (renamed to avoid ActiveRecord conflict)
      t.string :session_id                        # For grouping related calls
      
      # Additional metadata
      t.jsonb :metadata, default: {}              # Flexible storage for provider-specific data
      t.boolean :cached_response, default: false  # Whether response was from cache
      t.string :environment                       # production, development, test
      
      t.timestamps
      
      # Indexes for common queries
      t.index :type
      t.index :service_name
      t.index :model_used
      t.index :status
      t.index :created_at
      t.index [:trackable_type, :trackable_id], name: 'idx_api_calls_trackable'
      t.index :batch_id
      t.index :request_id
      t.index :session_id
      t.index [:type, :created_at]  # For provider-specific reporting
      t.index [:type, :model_used, :created_at]  # For model cost analysis
      t.index [:service_name, :status, :created_at]  # For service health monitoring
      t.index [:user_id, :created_at]  # For user usage tracking
    end
  end
end