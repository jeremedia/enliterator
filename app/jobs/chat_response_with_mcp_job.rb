# Chat Response Job with MCP Tools Integration
#
# This job enables the chat interface to use the MCP tools we've built,
# allowing it to search the knowledge graph, extract entities, analyze pools, etc.
#
class ChatResponseWithMcpJob < ApplicationJob
  queue_as :default
  
  def perform(conversation_id:, message_id:)
    @conversation_id = conversation_id  # Store for error reporting
    @message_id = message_id  # Store for error reporting
    conversation = Conversation.find(conversation_id)
    user_message = conversation.messages.find(message_id)
    assistant_message = nil
    
    begin
      # Create assistant message placeholder with initial trace
      assistant_message = conversation.messages.create!(
        role: 'assistant',
        content: '🔄 Initializing MCP tools...',
        metadata: {
          streaming: false,  # MCP responses don't stream the same way
          model_used: conversation.ai_model,
          started_at: Time.current,
          mcp_trace: ['🔄 Starting MCP tools...']
        }
      )
      
      # Broadcast the message container
      Rails.logger.info "Broadcasting assistant message to conversation_#{conversation.id}"
      Turbo::StreamsChannel.broadcast_append_to(
        "conversation_#{conversation.id}",
        target: "messages",
        partial: "ekns/chat/message",
        locals: { message: assistant_message, ekn: conversation.ekn }
      )
      
      # Test broadcast to verify channel connectivity
      Rails.logger.info "Testing Turbo Stream channel connectivity..."
      Turbo::StreamsChannel.broadcast_update_to(
        "conversation_#{conversation.id}",
        target: "message-#{assistant_message.id}-content",
        html: "<div class='text-blue-600 animate-pulse'>🔗 Channel connected, MCP processing starting...</div>"
      )
      
      # Build messages for OpenAI
      update_trace(conversation, assistant_message, "Preparing conversation context...")
      messages = build_messages_for_openai(conversation)
      
      # Call OpenAI with MCP tools enabled (this handles streaming in real-time)
      update_trace(conversation, assistant_message, "Connecting to MCP server...")
      response = call_openai_with_mcp(conversation, messages, assistant_message)
      
      # The streaming was already handled in call_openai_with_mcp
      # Just finalize the response metadata
      process_mcp_response(conversation, assistant_message, response)
      
    rescue => e
      Rails.logger.error "ChatResponseWithMcpJob failed: #{e.class} - #{e.message}"
      Rails.logger.error e.backtrace.first(10).join("\n")
      
      # ALWAYS handle the error and show it to user
      handle_error(conversation, assistant_message, e)
      
      # Ensure we broadcast that processing is complete
      Turbo::StreamsChannel.broadcast_update_to(
        "conversation_#{conversation.id}",
        target: "typing-indicator",
        html: ""
      )
    ensure
      # Always hide typing indicator
      broadcast_typing_indicator(conversation, typing: false) rescue nil
    end
  end
  
  private
  
  def build_messages_for_openai(conversation)
    messages = []
    
    # System message with EKN context
    system_prompt = build_system_prompt(conversation.ekn)
    messages << { role: "system", content: system_prompt }
    
    # Add conversation history
    conversation.messages.where(role: ['user', 'assistant']).order(:created_at).each do |msg|
      messages << { role: msg.role, content: msg.content }
    end
    
    messages
  end
  
  def build_system_prompt(ekn)
    # Get item count safely
    item_count = begin
      if ekn.ingest_batches.any?
        ekn.ingest_batches.count * 100  # Estimate if column doesn't exist
      else
        "multiple"
      end
    rescue
      "multiple"
    end
    
    <<~PROMPT
      You are an Enliterated Knowledge Navigator for the #{ekn.name} dataset.
      
      You have access to a knowledge graph with #{item_count} items
      organized according to the Ten Pool Canon framework.
      
      CRITICAL: You MUST use the MCP tools for ANY query about the knowledge graph, including:
      - Listing nodes, entities, or items (use search with appropriate pool filters)
      - Finding specific information (use search then fetch for details)
      - Understanding relationships (use bridge to find connections)
      - Analyzing text (use extract_and_link or analyze_pools)
      
      The Ten Pool Canon categories are:
      - Idea: Concepts, frameworks, principles
      - Practical: Methods, processes, implementations
      - Experience: Stories, observations, testimonials
      - Manifest: Physical objects, places, artifacts
      - Character: People, personas, agents
      - Time: Events, periods, temporal markers
      - Space: Locations, coordinates, spatial relationships
      - Lifecycle: Stages, transitions, progressions
      - Symbolic: Symbols, representations, meanings
      - Relator: Relationships, connections, associations
      
      For queries like "What nodes are available?" or "List all X":
      1. Use search with appropriate pools parameter to filter by type
      2. Use fetch to get details on specific nodes
      3. Show the actual data with IDs and citations
      
      ALWAYS provide specific node IDs, titles, and pools when listing entities.
      When you use tools, briefly mention what you're searching for.
    PROMPT
  end
  
  def call_openai_with_mcp(conversation, messages, assistant_message)
    ekn = conversation.ekn
    mcp_server_url = determine_mcp_url(ekn)
    
    Rails.logger.info "Calling OpenAI with MCP streaming enabled for EKN #{ekn.id}"
    Rails.logger.info "MCP Server URL: #{mcp_server_url}"
    
    update_trace(conversation, assistant_message, "Registering MCP tools with OpenAI...")
    
    # Use the streaming Responses API with MCP tools (like the OpenAI example)
    stream = OPENAI.responses.stream(
      model: conversation.ai_model || OpenaiConfig::SettingsManager.model_for(:answer),
      input: messages,  # Responses API uses 'input' not 'messages'
      tools: [
        {
          type: "mcp",
          server_label: "enliterator",
          server_url: mcp_server_url,
          require_approval: "never",  # Since we trust our own server
          headers: {
            "Authorization": "Bearer #{ENV['MCP_API_KEY'] || 'test-key-123'}",
            # Pass tracking metadata through headers
            "X-Message-Id": assistant_message.id.to_s,
            "X-Conversation-Id": conversation.id.to_s,
            "X-Ekn-Id": ekn.id.to_s
          },
          # Only include the tools we want the model to use
          allowed_tools: ["search", "fetch", "bridge", "extract_and_link", "analyze_pools"]
        }
      ]
    )
    
    # Process stream events in real-time
    stream_mcp_response(conversation, assistant_message, stream)
    
    # Get final response for metadata extraction
    final_response = stream.get_final_response()
    Rails.logger.info "Final MCP response received with #{final_response.output&.size || 0} outputs"
    
    final_response
  end
  
  def determine_mcp_url(ekn)
    # OpenAI needs a publicly accessible URL
    # In development, use the dev domain if available
    if ENV['APP_DOMAIN'].present?
      "https://#{ENV['APP_DOMAIN']}/api/v1/mcp/sse/"
    elsif Rails.env.production?
      "https://#{Rails.application.config.app_domain}/api/v1/mcp/sse/"
    else
      # Fallback - won't work with OpenAI but useful for error messages
      Rails.logger.warn "MCP tools require a public URL. Set APP_DOMAIN env var."
      "http://localhost:#{ENV['PORT'] || 3077}/api/v1/mcp/sse/"
    end
  end
  
  def stream_mcp_response(conversation, assistant_message, stream)
    Rails.logger.info "Starting real-time MCP streaming..."
    
    tool_calls_count = 0
    text_accumulator = ""
    
    stream.each do |event|
      Rails.logger.info "MCP Stream event: #{event.class.name} - #{event.inspect}"
      
      # Log all available methods/attributes for debugging
      Rails.logger.info "Event methods: #{event.class.instance_methods(false)}"
      
      # Handle ALL events by checking their properties rather than exact class matching
      if event.respond_to?(:delta) && event.delta.present?
        # This is likely a text delta event
        text_accumulator += event.delta
        update_trace(conversation, assistant_message, "📝 Receiving text (#{text_accumulator.length} chars)...")
        
        # Stream partial content to user (every 100 chars)
        if text_accumulator.length > 50 && text_accumulator.length % 100 < event.delta.length
          broadcast_streaming_content(conversation, assistant_message, text_accumulator)
        end
        
      elsif event.respond_to?(:function) && event.function.present?
        # This is likely a function call event
        if event.function.respond_to?(:name) && event.function.name.present?
          tool_calls_count += 1
          update_trace(conversation, assistant_message, "🔧 Calling #{event.function.name}...")
          
          # Track the tool call
          tool_call = {
            name: event.function.name,
            arguments: event.function.respond_to?(:arguments) ? event.function.arguments : {},
            timestamp: Time.current.strftime("%I:%M:%S %p"),
            id: event.respond_to?(:id) ? event.id : "unknown"
          }
          
          # Update tool calls metadata
          current_tool_calls = assistant_message.metadata['tool_calls'] || []
          current_tool_calls << tool_call
          assistant_message.update!(
            metadata: assistant_message.metadata.merge('tool_calls' => current_tool_calls)
          )
          
          # Broadcast tool update
          broadcast_tool_calls_update(conversation, assistant_message, current_tool_calls)
        end
        
      elsif event.respond_to?(:result) && event.result.present?
        # This is likely a tool result event
        update_trace(conversation, assistant_message, "✓ Tool completed")
        
      else
        # Log unhandled events for debugging
        update_trace(conversation, assistant_message, "🔄 Processing #{event.class.name.split('::').last}...")
      end
    end
    
    Rails.logger.info "MCP streaming complete. Tool calls: #{tool_calls_count}, Text length: #{text_accumulator.length}"
    
    # Update trace with final summary
    if tool_calls_count > 0
      update_trace(conversation, assistant_message, "✅ Used #{tool_calls_count} tool(s) to gather information")
    end
    
    # Broadcast final accumulated text
    if text_accumulator.present?
      broadcast_streaming_content(conversation, assistant_message, text_accumulator)
    end
    
    update_trace(conversation, assistant_message, "✨ Response ready")
  rescue => e
    Rails.logger.error "MCP streaming error: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    update_trace(conversation, assistant_message, "❌ Streaming error: #{e.message}")
    raise e
  end
  
  def broadcast_streaming_content(conversation, assistant_message, content)
    # Update the message content
    assistant_message.update!(
      content: content,
      metadata: assistant_message.metadata.merge(streaming: true)
    )
    
    # Just update the content value and let the Stimulus controller handle the rendering
    # This avoids double-processing the markdown (server + client)
    escaped_content = CGI.escapeHTML(content)
    Turbo::StreamsChannel.broadcast_update_to(
      "conversation_#{conversation.id}",
      target: "message-#{assistant_message.id}-content",
      html: <<~HTML
        <div class="prose prose-sm max-w-none"
             data-controller="markdown"
             data-markdown-content-value="#{escaped_content}"
             data-markdown-streaming-value="true">
          <div class="text-gray-500 italic animate-pulse">Streaming...</div>
        </div>
      HTML
    )
  end

  def process_mcp_response(conversation, assistant_message, response)
    Rails.logger.info "Processing final MCP response with #{response.output&.size || 0} outputs"
    
    # Extract all MCP events for metadata
    mcp_events = extract_mcp_events(response)
    
    # Extract the final text response
    final_text = extract_text_from_response(response)
    
    # Extract any MCP tool calls that were made
    tool_calls = extract_tool_calls(response)
    
    # Get final traces for metadata (streaming already updated them)
    traces = assistant_message.metadata['mcp_trace'] || []
    
    # Update the assistant message with final content and metadata
    assistant_message.update!(
      content: final_text,
      metadata: assistant_message.metadata.merge(
        model_used: response.model,
        usage: response.usage&.to_h,
        tool_calls: tool_calls,
        mcp_events: mcp_events,
        mcp_trace: traces,
        completed_at: Time.current,
        streaming: false  # No longer streaming
      )
    )
    
    # Broadcast the final complete message (ensures content is final)
    broadcast_message_update(conversation, assistant_message)
    
    # Log what tools were used
    if tool_calls.any?
      Rails.logger.info "MCP tools used: #{tool_calls.map { |tc| tc[:name] }.join(', ')}"
    else
      Rails.logger.info "No MCP tools were used in this response"
    end
  end
  
  def extract_text_from_response(response)
    # The Responses API with MCP returns output_text directly
    if response.respond_to?(:output_text) && response.output_text.present?
      return response.output_text
    end
    
    # Fallback: look for message or text items in output
    response.output.each do |item|
      case item.type
      when 'message'
        return item.content if item.respond_to?(:content)
      when 'text'
        return item.text if item.respond_to?(:text)
      end
    end
    
    "I couldn't generate a response."
  end
  
  def extract_tool_calls(response)
    tool_calls = []
    
    # Debug logging (can be removed later)
    Rails.logger.debug "Extracting tool calls from response: #{response.class.name}"
    
    # First check if response has tool_calls directly
    if response.respond_to?(:tool_calls) && response.tool_calls.present?
      Rails.logger.info "Found tool_calls directly on response: #{response.tool_calls.size} calls"
      response.tool_calls.each do |call|
        tool_call = extract_tool_call_details(call)
        tool_calls << tool_call if tool_call
      end
    end
    
    # Look for MCP tool call items in the output
    if response.respond_to?(:output) && response.output.present?
      Rails.logger.info "Checking output array with #{response.output.size} items"
      
      response.output.each_with_index do |item, idx|
        if item.respond_to?(:type)
          Rails.logger.debug "Output[#{idx}] type: '#{item.type}' (#{item.type.class.name}), class: #{item.class.name}"
        end
        
        # Check if this is an MCP call - also check class name
        if (item.respond_to?(:type) && item.type == 'mcp_call') || 
           item.class.name == 'OpenAI::Models::Responses::ResponseOutputItem::McpCall'
          Rails.logger.info "Found MCP call at index #{idx}!"
          Rails.logger.info "  Item has name? #{item.respond_to?(:name)}, value: #{item.name if item.respond_to?(:name)}"
          
          # The MCP Call items have name, id, arguments, server_label, output properties
          tool_call = {
            name: item.respond_to?(:name) ? item.name : 'unknown',
            timestamp: Time.current.strftime("%I:%M:%S %p")
          }
          
          # Add other available properties
          tool_call[:id] = item.id if item.respond_to?(:id) && item.id
          tool_call[:arguments] = item.arguments if item.respond_to?(:arguments) && item.arguments
          tool_call[:server_label] = item.server_label if item.respond_to?(:server_label) && item.server_label
          
          # Parse the output if it's JSON
          if item.respond_to?(:output) && item.output
            begin
              tool_call[:result] = JSON.parse(item.output)
            rescue JSON::ParserError
              tool_call[:result] = item.output
            end
          end
          
          tool_calls << tool_call
          Rails.logger.info "Extracted tool call: #{tool_call[:name]} with id: #{tool_call[:id]}"
        end
      end
    end
    
    # Also check metadata for tool information
    if response.respond_to?(:metadata) && response.metadata.is_a?(Hash)
      if response.metadata['tool_calls'].present?
        Rails.logger.info "Found tool_calls in metadata: #{response.metadata['tool_calls'].size}"
        response.metadata['tool_calls'].each do |call|
          tool_calls << normalize_tool_call(call)
        end
      end
    end
    
    Rails.logger.info "Total tool calls extracted: #{tool_calls.size}"
    tool_calls.uniq { |tc| "#{tc[:name]}_#{tc[:timestamp]}" }  # Remove duplicates
  end
  
  def extract_tool_call_details(item)
    return nil unless item
    
    tool_call = {
      name: 'unknown',
      timestamp: Time.current.strftime("%I:%M:%S %p")
    }
    
    # Try various property names
    [:name, :tool_name, :function_name, :tool].each do |prop|
      if item.respond_to?(prop) && item.send(prop).present?
        tool_call[:name] = item.send(prop)
        break
      end
    end
    
    # Extract other properties
    tool_call[:id] = item.id if item.respond_to?(:id)
    tool_call[:arguments] = item.arguments if item.respond_to?(:arguments)
    tool_call[:output] = item.output if item.respond_to?(:output)
    tool_call[:result] = item.result if item.respond_to?(:result)
    tool_call[:server_label] = item.server_label if item.respond_to?(:server_label)
    
    Rails.logger.info "Extracted tool call: #{tool_call[:name]} with args: #{tool_call[:arguments]&.to_s&.truncate(100)}"
    tool_call
  end
  
  def normalize_tool_call(call)
    # Normalize various tool call formats
    return call if call.is_a?(Hash) && call[:name].present?
    
    {
      name: call['name'] || call['tool_name'] || call['function'] || 'unknown',
      arguments: call['arguments'] || call['params'],
      timestamp: call['timestamp'] || Time.current.strftime("%I:%M:%S %p")
    }
  end
  
  def extract_mcp_events(response)
    events = []
    
    # Capture all MCP-related events for debugging
    if response.respond_to?(:output) && response.output.present?
      response.output.each do |item|
        if item.respond_to?(:type)
          event = case item.type
          when 'mcp_list_tools'
            { 
              type: 'tools_listed', 
              tools: item.tools&.map(&:name),
              count: item.tools&.size || 0
            }
          when 'mcp_call', 'tool_call', 'mcp_tool_call'
            # Extract all available properties from the mcp_call item
            event = { 
              type: 'mcp_call',
              name: item.respond_to?(:name) ? item.name : nil,
              id: item.respond_to?(:id) ? item.id : nil,
              arguments: item.respond_to?(:arguments) ? item.arguments : nil,
              server_label: item.respond_to?(:server_label) ? item.server_label : nil,
              has_result: item.respond_to?(:output) && item.output.present?
            }
            
            # Parse output if available
            if item.respond_to?(:output) && item.output.present?
              begin
                event[:output] = JSON.parse(item.output)
              rescue JSON::ParserError
                event[:output] = item.output
              end
            end
            
            Rails.logger.debug "Extracted MCP call event: name=#{event[:name]}, id=#{event[:id]}"
            event
          when 'message'
            { type: 'message_generated' }
          else
            { type: item.type }
          end
          
          events << event
          Rails.logger.debug "MCP Event: #{event.inspect}"
        end
      end
    end
    
    Rails.logger.info "Total MCP events captured: #{events.size}, Tool calls: #{events.count { |e| e[:type] == 'tool_called' }}"
    events
  end
  
  def broadcast_message_update(conversation, message)
    Turbo::StreamsChannel.broadcast_replace_to(
      "conversation_#{conversation.id}",
      target: "message_#{message.id}",
      partial: "ekns/chat/message",
      locals: { message: message, ekn: conversation.ekn }
    )
  end
  
  def broadcast_typing_indicator(conversation, typing:)
    if typing
      Turbo::StreamsChannel.broadcast_append_to(
        "conversation_#{conversation.id}",
        target: "messages",
        partial: "ekns/chat/typing_indicator"
      )
    else
      Turbo::StreamsChannel.broadcast_remove_to(
        "conversation_#{conversation.id}",
        target: "typing_indicator"
      )
    end
  end
  
  def handle_error(conversation, assistant_message, error)
    Rails.logger.error "ChatResponseWithMcpJob Error: #{error.class} - #{error.message}"
    Rails.logger.error error.backtrace.first(5).join("\n")
    
    # Format error message for user
    error_message = format_error_for_user(error)
    
    if assistant_message
      # Update the message with error details
      assistant_message.update!(
        content: error_message,
        metadata: assistant_message.metadata.merge(
          error: error.message,
          error_class: error.class.name,
          error_backtrace: error.backtrace.first(3),
          completed_at: Time.current,
          is_error: true
        )
      )
      
      # CRITICAL: Ensure the error is broadcast immediately
      # First, try to replace if the message exists in DOM
      broadcast_message_update(conversation, assistant_message)
      
      # Also append a specific error notification
      broadcast_error_notification(conversation, assistant_message, error)
    else
      # Create error message if we couldn't create assistant message
      error_msg = conversation.messages.create!(
        role: 'assistant',
        content: error_message,
        metadata: { 
          error: error.message,
          error_class: error.class.name,
          is_error: true,
          completed_at: Time.current
        }
      )
      
      # Broadcast the error message
      Turbo::StreamsChannel.broadcast_append_to(
        "conversation_#{conversation.id}",
        target: "messages",
        partial: "ekns/chat/message",
        locals: { message: error_msg, ekn: conversation.ekn }
      )
      
      broadcast_error_notification(conversation, error_msg, error)
    end
    
    # ALWAYS hide typing indicator on error
    broadcast_typing_indicator(conversation, typing: false)
  end
  
  def format_error_for_user(error)
    # During development, provide FULL debugging information
    debug_info = if Rails.env.development?
      <<~DEBUG
        
        🔍 **Debug Information:**
        - **Error Class**: #{error.class.name}
        - **Phase**: ChatResponseWithMcpJob#call_openai_with_mcp
        - **Conversation ID**: #{@conversation_id || 'unknown'}
        - **Message ID**: #{@message_id || 'unknown'}
        - **Timestamp**: #{Time.current}
        - **Backtrace** (first 3 lines):
        #{error.backtrace.first(3).map { |line| "  #{line}" }.join("\n")}
      DEBUG
    else
      ""
    end
    
    case error
    when ActiveRecord::StatementInvalid
      if error.message.include?("column")
        "❌ Database configuration error: A required database column is missing.\n\nTechnical details: #{error.message.split('\n').first}#{debug_info}"
      else
        "❌ Database error occurred.\n\nError: #{error.message.split('\n').first}#{debug_info}"
      end
    when Net::OpenTimeout, Net::ReadTimeout
      "❌ Connection timeout: The AI service is taking too long to respond.#{debug_info}"
    when StandardError
      if error.message.include?("401")
        "❌ Authentication error: Unable to connect to AI service.\n\nDetails: #{error.message}#{debug_info}"
      elsif error.message.include?("rate_limit")
        "❌ Rate limit exceeded: Too many requests.\n\nDetails: #{error.message}#{debug_info}"
      elsif error.message.include?("stream")
        "❌ API Configuration Error: #{error.message}\n\nThis likely means the API call is using incorrect parameters.#{debug_info}"
      else
        "❌ Error: #{error.message}#{debug_info}"
      end
    else
      "❌ Unexpected error: #{error.message}#{debug_info}"
    end
  end
  
  def broadcast_error_notification(conversation, message, error)
    # Broadcast a specific error notification that will always show
    Turbo::StreamsChannel.broadcast_prepend_to(
      "conversation_#{conversation.id}",
      target: "messages",
      html: <<~HTML
        <div class="bg-red-50 border-l-4 border-red-500 p-4 mb-4" id="error-#{message.id}">
          <div class="flex">
            <div class="flex-shrink-0">
              <svg class="h-5 w-5 text-red-400" viewBox="0 0 20 20" fill="currentColor">
                <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd"/>
              </svg>
            </div>
            <div class="ml-3">
              <h3 class="text-sm font-medium text-red-800">Error in AI Response</h3>
              <div class="mt-2 text-sm text-red-700">
                <p>#{error.class.name}: #{error.message.split('\n').first.truncate(200)}</p>
              </div>
            </div>
          </div>
        </div>
      HTML
    )
  end
  
  def update_trace(conversation, assistant_message, trace_message)
    # Add to trace history
    traces = assistant_message.metadata['mcp_trace'] || []
    traces << trace_message
    
    # Update the message metadata (but NOT the content yet)
    assistant_message.update!(
      metadata: assistant_message.metadata.merge('mcp_trace' => traces)
    )
    
    # Build trace HTML directly instead of using ApplicationController.render
    trace_html = build_trace_html(traces)
    
    # Add a small delay for the first trace to ensure DOM element exists
    if traces.size == 1
      sleep(0.1)
      Rails.logger.info "Added delay for first trace update"
    end
    
    # Broadcast JUST the trace update in real-time
    # Use update to update the content inside the trace container, not replace the entire container
    begin
      Turbo::StreamsChannel.broadcast_update_to(
        "conversation_#{conversation.id}",
        target: "message-#{assistant_message.id}-trace",
        html: trace_html
      )
      Rails.logger.info "✅ Successfully broadcast trace update"
    rescue => e
      Rails.logger.error "❌ Trace broadcast failed: #{e.message}"
    end
    
    Rails.logger.info "MCP Trace: #{trace_message} (total: #{traces.size})"
    Rails.logger.info "Broadcasting trace update to: conversation_#{conversation.id} target: message-#{assistant_message.id}-trace"
    Rails.logger.info "Trace HTML length: #{trace_html.length}"
  end
  
  def build_trace_html(traces)
    return "" if traces.empty?
    
    trace_lines = traces.map do |trace|
      "<div class=\"ml-2 trace-line\">#{CGI.escapeHTML(trace)}</div>"
    end.join
    
    # Show trace count and latest trace in header
    latest_trace = traces.last
    trace_count = traces.size
    
    <<~HTML
      <details class="mb-2">
        <summary class="cursor-pointer p-2 bg-gray-50 rounded text-xs text-gray-600 font-mono hover:bg-gray-100 transition-colors">
          <span class="font-semibold">🔍 Process Trace (#{trace_count})</span>
          <span class="ml-2 text-gray-500 animate-pulse">#{CGI.escapeHTML(latest_trace)}</span>
        </summary>
        <div class="mt-2 p-2 bg-gray-50 rounded text-xs text-gray-600 font-mono max-h-48 overflow-y-auto">
          #{trace_lines}
        </div>
      </details>
    HTML
  end
  
  # DEPRECATED: This method is no longer used since we implemented real streaming
  # via the OpenAI Responses API stream() method in stream_mcp_response()
  # Keeping as reference for now, but can be removed in next cleanup
  
  def process_stream_chunk(conversation, assistant_message, chunk)
    # Handle different types of streaming events IN REAL TIME
    Rails.logger.debug "Stream chunk type: #{chunk.respond_to?(:type) ? chunk.type : 'no type'}"
    
    if chunk.respond_to?(:type)
      case chunk.type
      when 'mcp_list_tools'
        if chunk.respond_to?(:tools)
          tools = chunk.tools.map(&:name).join(', ')
          update_trace(conversation, assistant_message, "✅ Tools available: #{tools}")
        end
      when 'mcp_call', 'tool_call', 'mcp_tool_call'
        # Extract tool name using various possible properties
        tool_name = if chunk.respond_to?(:name)
          chunk.name
        elsif chunk.respond_to?(:tool_name)
          chunk.tool_name
        elsif chunk.respond_to?(:function_name)
          chunk.function_name
        else
          'unknown'
        end
        
        # Real-time tool call notification
        update_trace(conversation, assistant_message, "🔧 Calling tool: #{tool_name}")
        
        # Also update tool calls display
        tool_calls = assistant_message.metadata['tool_calls'] || []
        tool_call = {
          name: tool_name,
          arguments: chunk.respond_to?(:arguments) ? chunk.arguments : nil,
          timestamp: Time.current.strftime("%I:%M:%S %p")
        }
        tool_calls << tool_call
        
        assistant_message.update!(
          metadata: assistant_message.metadata.merge('tool_calls' => tool_calls)
        )
        
        # Broadcast tool update immediately
        broadcast_tool_calls_update(conversation, assistant_message, tool_calls)
        
      when 'mcp_result', 'tool_result'
        result_name = chunk.respond_to?(:name) ? chunk.name : 'Tool'
        update_trace(conversation, assistant_message, "✓ #{result_name} returned results")
        
      when 'message_start'
        update_trace(conversation, assistant_message, "💭 Generating response...")
        
      when 'content_block_delta'
        # Stream content updates
        if chunk.respond_to?(:delta) && chunk.delta.respond_to?(:text)
          current_content = assistant_message.content || ""
          assistant_message.update!(content: current_content + chunk.delta.text)
          
          # Broadcast content update
          Turbo::StreamsChannel.broadcast_replace_to(
            "conversation_#{conversation.id}",
            target: "message-#{assistant_message.id}-content",
            html: "<div class='prose prose-sm max-w-none'>#{render_markdown(assistant_message.content)}</div>"
          )
        end
      else
        Rails.logger.debug "Unhandled stream chunk type: #{chunk.type}"
      end
    end
  end
  
  def broadcast_tool_calls_update(conversation, assistant_message, tool_calls)
    # Broadcast tool calls update - use update_to to preserve the container ID
    Rails.logger.info "🔧 Broadcasting tool calls update: #{tool_calls.size} calls to message-#{assistant_message.id}-tools"
    
    Turbo::StreamsChannel.broadcast_update_to(
      "conversation_#{conversation.id}",
      target: "message-#{assistant_message.id}-tools",
      html: render_tool_calls(tool_calls)
    )
    
    Rails.logger.info "✅ Tool calls broadcast complete"
  end
  
  def render_tool_calls(tool_calls)
    return "" if tool_calls.empty?
    
    # Get latest tool and count for summary
    latest_tool = tool_calls.last
    tool_count = tool_calls.size
    
    html = <<~HTML
      <details class="mb-2">
        <summary class="cursor-pointer p-2 bg-gray-50 rounded text-xs text-gray-600 font-mono hover:bg-gray-100 transition-colors">
          <span class="font-semibold">🔧 Tools Used (#{tool_count})</span>
          <span class="ml-2 text-gray-500">#{latest_tool[:name]}</span>
        </summary>
        <div class="mt-2 p-2 bg-gray-50 rounded text-xs text-gray-600 font-mono max-h-48 overflow-y-auto">
          #{tool_calls.map { |tc| 
            "<div class='ml-2 tool-call'>
              <span class='font-medium'>#{tc[:name]}</span>
              <span class='text-gray-400 text-xs ml-2'>#{tc[:timestamp]}</span>
            </div>"
          }.join}
        </div>
      </details>
    HTML
    
    html
  end
  
  def render_markdown(content)
    # Simple markdown rendering - you might want to use a proper markdown renderer
    content.gsub(/\n/, '<br>')
  end
end