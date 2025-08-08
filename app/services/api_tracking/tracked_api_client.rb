# frozen_string_literal: true

module ApiTracking
  # Universal API client wrapper that tracks all API calls
  # Intercepts method calls, logs them, and stores complete responses
  class TrackedApiClient
    attr_reader :provider, :client, :cache_enabled

    def initialize(provider:, client:, cache_enabled: true)
      @provider = provider
      @client = client
      @cache_enabled = cache_enabled
      @provider_adapter = load_provider_adapter(provider)
    end

    # Intercept all method calls to the wrapped client
    def method_missing(method_name, *args, **kwargs, &block)
      # Check if the client responds to this method
      unless @client.respond_to?(method_name)
        super
      end

      # If this is a method with arguments, it's likely a direct call
      if args.any? || kwargs.any? || block_given?
        # Direct API call, track it
        track_direct_call(method_name, args, kwargs, &block)
      else
        # This returns an intermediate object (like client.chat)
        # Build a chain to track the eventual call
        ChainBuilder.new(@client, [ method_name ], @provider, @provider_adapter, @cache_enabled)
      end
    end

    def respond_to_missing?(method_name, include_private = false)
      @client.respond_to?(method_name) || super
    end

    private

    def load_provider_adapter(provider)
      case provider.to_s.downcase
      when "openai"
        ProviderAdapters::OpenaiAdapter.new
      when "anthropic"
        ProviderAdapters::AnthropicAdapter.new
      when "ollama"
        ProviderAdapters::OllamaAdapter.new
      else
        ProviderAdapters::GenericAdapter.new
      end
    end

    def track_direct_call(method_name, args, kwargs, &block)
      # Execute with tracking using ChainBuilder
      builder = ChainBuilder.new(@client, [ method_name ], @provider, @provider_adapter, @cache_enabled)
      builder.execute_direct(args, kwargs, &block)
    end

    # Handles method chaining like client.chat.completions.create
    class ChainBuilder
      def initialize(client, method_chain, provider, provider_adapter, cache_enabled)
        @client = client
        @method_chain = method_chain
        @provider = provider
        @provider_adapter = provider_adapter
        @cache_enabled = cache_enabled
        @final_args = []
        @final_kwargs = {}
        @block = nil
      end
      
      # Prevent implicit conversion to Array which causes errors
      def to_ary
        nil
      end
      
      # Add to_a method that returns nil to prevent array conversion
      def to_a
        nil
      end

      def method_missing(method_name, *args, **kwargs, &block)
        @method_chain << method_name
        if args.any? || kwargs.any? || block_given?
          # This is the final call in the chain
          @final_args = args
          @final_kwargs = kwargs
          @block = block
          execute_with_tracking
        else
          # Continue building the chain
          self
        end
      end

      def respond_to_missing?(method_name, include_private = false)
        true # Accept any method in the chain
      end

      # Execute a direct call (no further chaining)
      def execute_direct(args, kwargs, &block)
        @final_args = args
        @final_kwargs = kwargs
        @block = block
        execute_with_tracking
      end

      def execute_with_tracking
        # Bypass tracking for typed SDK list endpoint that returns a paginated Page
        # Some SDKs (like openai-ruby) expect an exact wire shape for list responses.
        # Wrapping/marshalling can alter the shape and break the Page initializer.
        # We therefore call the underlying client directly for models.list.
        if @method_chain.join(".") == "models.list"
          begin
            return @client.models.list
          rescue => e
            # If the direct call fails, re-raise so callers can handle/log as usual
            raise
          end
        end

        # Build the full endpoint name
        endpoint = @method_chain.join(".")

        # Generate cache key from request
        cache_key = generate_cache_key(endpoint, @final_args, @final_kwargs)

        # Check cache first if enabled
        if @cache_enabled
          cached_response = check_cache(@provider, cache_key)
          if cached_response
            Rails.logger.info "[TrackedApiClient] Cache hit for #{@provider}:#{endpoint}"
            return cached_response
          end
        end

        # Create tracking record
        api_call = create_api_call(@provider, endpoint, @provider_adapter)

        # Execute the actual API call
        result = api_call.track_execution do |call|
          begin
            # Navigate through the method chain
            target = @client
            @method_chain[0...-1].each do |method|
              target = target.send(method)
            end

            # Make the final call
            response = if @block
              target.send(@method_chain.last, *@final_args, **@final_kwargs, &@block)
            elsif @final_kwargs.any?
              target.send(@method_chain.last, *@final_args, **@final_kwargs)
            else
              target.send(@method_chain.last, *@final_args)
            end

            # Store complete response
            call.response_data = serialize_response(response)
            call.response_cache_key = cache_key

            # Extract usage data through adapter
            @provider_adapter.extract_usage_data(call, response)

            response
          rescue => e
            call.error_code = e.class.name
            call.error_message = e.message
            call.error_details = {
              backtrace: e.backtrace&.first(10),
              args: @final_args,
              kwargs: @final_kwargs
            }
            raise
          end
        end

        result
      end

      private

      def generate_cache_key(endpoint, args, kwargs)
        # Create a deterministic cache key
        content = {
          endpoint: endpoint,
          args: args,
          kwargs: kwargs.sort.to_h  # Sort kwargs for consistency
        }

        Digest::SHA256.hexdigest(content.to_json)
      end

      def check_cache(provider, cache_key)
        # Check for recent cached response
        cached = ApiCall
          .where(type: "#{provider.capitalize}ApiCall")
          .where(response_cache_key: cache_key)
          .where(status: "success")
          .where("created_at > ?", cache_duration.ago)
          .order(created_at: :desc)
          .first

        if cached && cached.response_data.present?
          # Deserialize and return the cached response
          deserialize_response(cached.response_data, cached.type)
        end
      end

      def cache_duration
        # Different cache durations for different types
        case @method_chain.join(".")
        when /embeddings/
          1.week  # Embeddings are stable
        when /models\.list/
          1.day   # Model lists change rarely
        when /chat\.completions/
          1.hour  # Chat responses might vary
        else
          30.minutes  # Default cache duration
        end
      end

      def create_api_call(provider, endpoint, adapter)
        klass = "#{provider.capitalize}ApiCall".constantize

        klass.new(
          service_name: find_service_name,
          endpoint: endpoint,
          request_params: {
            args: @final_args,
            kwargs: @final_kwargs
          },
          status: "pending",
          user: ApiCall.current_user,
          ekn: ApiCall.current_ekn,
          session: ApiCall.current_session,
          environment: Rails.env
        )
      end

      def find_service_name
        # Try to determine the service name from the call stack
        caller_locations.each do |location|
          if location.path.include?("/app/services/")
            # Extract service class name
            path = location.path.split("/app/services/").last
            return path.gsub("/", "::").gsub(".rb", "").camelize
          elsif location.path.include?("/app/jobs/")
            # Extract job class name
            path = location.path.split("/app/jobs/").last
            return path.gsub("/", "::").gsub(".rb", "").camelize + " (Job)"
          end
        end

        "TrackedApiClient::Direct"
      end

      def serialize_response(response)
        case response
        when Hash
          response
        when String
          { text: response }
        when Numeric
          { value: response }
        else
          # Try to convert to hash
          if response.respond_to?(:to_h)
            response.to_h
          elsif response.respond_to?(:to_json)
            JSON.parse(response.to_json)
          else
            {
              class: response.class.name,
              value: response.to_s,
              inspection: response.inspect
            }
          end
        end
      rescue => e
        {
          serialization_error: e.message,
          class: response.class.name,
          inspection: response.inspect[0..1000]  # Truncate for safety
        }
      end

      def deserialize_response(data, provider_type)
        # Convert stored data back to appropriate response object
        case provider_type
        when "OpenaiApiCall"
          # OpenAI responses need to be properly structured
          # The gem returns structured objects with nested attributes
          if data.is_a?(Hash)
            # Create nested OpenStruct objects for proper API compatibility
            JSON.parse(data.to_json, object_class: OpenStruct)
          else
            data
          end
        when "AnthropicApiCall"
          # Anthropic might use different structure
          JSON.parse(data.to_json, object_class: OpenStruct)
        else
          data
        end
      end
    end
  end
end
