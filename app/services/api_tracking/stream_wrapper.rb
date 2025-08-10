# frozen_string_literal: true

module ApiTracking
  # Wrapper for streaming responses that tracks usage without consuming the stream
  class StreamWrapper
    attr_reader :original_stream, :api_call, :provider_adapter
    
    def initialize(original_stream, api_call, provider_adapter)
      @original_stream = original_stream
      @api_call = api_call
      @provider_adapter = provider_adapter
      @stream_completed = false
      @usage_data = {}
    end
    
    # Make it enumerable - this is the key method for streaming
    def each
      return enum_for(:each) unless block_given?
      
      begin
        Rails.logger.info "[StreamWrapper] Starting iteration over #{@original_stream.class}"
        event_count = 0
        @original_stream.each do |event|
          event_count += 1
          Rails.logger.debug "[StreamWrapper] Event #{event_count}: #{event.class.name}"
          
          # Track specific event types for usage (don't store the event object itself)
          track_event(event)
          
          # Pass the event through untouched
          yield event
        end
        Rails.logger.info "[StreamWrapper] Finished iteration, #{event_count} events"
      ensure
        # Stream is complete, finalize tracking
        finalize_tracking
      end
    end
    
    # Support the stream() method pattern
    def stream
      each
    end
    
    # Delegate other methods to the original stream
    def method_missing(method_name, *args, **kwargs, &block)
      if @original_stream.respond_to?(method_name)
        @original_stream.send(method_name, *args, **kwargs, &block)
      else
        super
      end
    end
    
    def respond_to_missing?(method_name, include_private = false)
      @original_stream.respond_to?(method_name, include_private) || super
    end
    
    private
    
    def track_event(event)
      # Count total events
      @usage_data[:total_events] ||= 0
      @usage_data[:total_events] += 1
      
      # Track different event types for OpenAI streaming
      case event
      when defined?(OpenAI::Streaming::ResponseTextDeltaEvent) && OpenAI::Streaming::ResponseTextDeltaEvent,
           defined?(OpenAI::Helpers::Streaming::ResponseTextDeltaEvent) && OpenAI::Helpers::Streaming::ResponseTextDeltaEvent
        # Track text deltas
        @usage_data[:delta_count] ||= 0
        @usage_data[:delta_count] += 1
        @usage_data[:total_delta_length] ||= 0
        @usage_data[:total_delta_length] += event.delta.length if event.respond_to?(:delta)
        
      when defined?(OpenAI::Streaming::ResponseTextDoneEvent) && OpenAI::Streaming::ResponseTextDoneEvent,
           defined?(OpenAI::Helpers::Streaming::ResponseTextDoneEvent) && OpenAI::Helpers::Streaming::ResponseTextDoneEvent
        # Final event with parsed data and usage
        if event.respond_to?(:parsed)
          @usage_data[:final_parsed] = true
          
          # Try to extract token usage from the parsed response
          if event.parsed.respond_to?(:usage)
            extract_usage_from_parsed(event.parsed.usage)
          end
        end
        
        # The event might have usage data directly
        if event.respond_to?(:usage)
          extract_usage_from_parsed(event.usage)
        end
        
      when defined?(OpenAI::Streaming::ChatCompletionChunk) && OpenAI::Streaming::ChatCompletionChunk
        # Legacy chat completion streaming
        if event.respond_to?(:usage)
          extract_usage_from_parsed(event.usage)
        end
      end
    rescue => e
      Rails.logger.debug "[StreamWrapper] Error tracking event: #{e.message}"
    end
    
    def extract_usage_from_parsed(usage)
      return unless usage
      
      if usage.respond_to?(:prompt_tokens)
        @usage_data[:prompt_tokens] = usage.prompt_tokens
        @usage_data[:completion_tokens] = usage.completion_tokens
        @usage_data[:total_tokens] = usage.total_tokens
      elsif usage.is_a?(Hash)
        @usage_data[:prompt_tokens] = usage['prompt_tokens'] || usage[:prompt_tokens]
        @usage_data[:completion_tokens] = usage['completion_tokens'] || usage[:completion_tokens]
        @usage_data[:total_tokens] = usage['total_tokens'] || usage[:total_tokens]
      end
    end
    
    def finalize_tracking
      return if @stream_completed
      @stream_completed = true
      
      begin
        # Update the API call with collected data
        @api_call.response_data = {
          streaming: true,
          events_collected: @usage_data[:total_events] || 0,
          delta_count: @usage_data[:delta_count],
          total_delta_length: @usage_data[:total_delta_length],
          stream_completed: true
        }
        
        # Update token usage if we found it
        if @usage_data[:prompt_tokens]
          @api_call.prompt_tokens = @usage_data[:prompt_tokens]
          @api_call.completion_tokens = @usage_data[:completion_tokens]
          @api_call.total_tokens = @usage_data[:total_tokens]
        end
        
        # Calculate costs if we have token counts
        if @api_call.prompt_tokens && @api_call.completion_tokens
          @provider_adapter.calculate_costs(@api_call) if @provider_adapter.respond_to?(:calculate_costs)
        end
        
        # Mark as successful
        @api_call.status = 'success'
        @api_call.save!
        
        Rails.logger.info "[StreamWrapper] Stream completed: #{@usage_data[:delta_count]} deltas, #{@api_call.total_tokens} tokens"
      rescue => e
        Rails.logger.error "[StreamWrapper] Error finalizing tracking: #{e.message}"
      end
    end
  end
end