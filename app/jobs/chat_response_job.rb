# Response model for chat conversations using Responses API
class ChatResponse < OpenAI::Helpers::StructuredOutput::BaseModel
  required :answer, String, doc: "The response to the user's query"
  required :confidence, Float, doc: "Confidence score 0-1"
  required :reasoning, String, nil?: true, doc: "Internal reasoning for the response"
  required :resources_used, OpenAI::ArrayOf[String], nil?: true, doc: "MCP resources accessed"
end

class ChatResponseJob < ApplicationJob
  queue_as :default
  
  def perform(conversation_id:, message_id:)
    conversation = Conversation.find(conversation_id)
    user_message = conversation.messages.find(message_id)
    assistant_message = nil
    
    begin
      # Create assistant message placeholder
      assistant_message = conversation.messages.create!(
        role: 'assistant',
        content: '',
        metadata: {
          streaming: true,
          model_used: conversation.ai_model,
          started_at: Time.current
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
      
      # Build messages for OpenAI
      messages = build_messages_for_openai(conversation)
      
      # Stream response from OpenAI
      stream_response(conversation, assistant_message, messages)
      
    rescue => e
      Rails.logger.error "ChatResponseJob failed: #{e.class} - #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      handle_error(conversation, assistant_message, e)
    ensure
      # Hide typing indicator
      Rails.logger.info "Hiding typing indicator for conversation_#{conversation.id}"
      Turbo::StreamsChannel.broadcast_update_to(
        "conversation_#{conversation.id}",
        target: "typing-indicator",
        partial: "ekns/chat/typing_indicator",
        locals: { show: false, ekn: conversation&.ekn }
      )
    end
  end
  
  private
  
  def build_messages_for_openai(conversation)
    messages = []
    
    # Add system message for context
    if conversation.ekn.present?
      messages << {
        role: 'system',
        content: build_system_prompt(conversation.ekn)
      }
    end
    
    # Get the last user message
    last_user_message = conversation.messages.where(role: 'user').last
    
    # Use QueryOrchestrator to get relevant context if we have a user query
    knowledge_context = nil
    if last_user_message && conversation.ekn
      begin
        Rails.logger.info "Using QueryOrchestrator for: #{last_user_message.content}"
        orchestrator = QueryOrchestrator.new(ekn: conversation.ekn, conversation: conversation)
        orchestration_result = orchestrator.process(last_user_message.content)
        
        if orchestration_result && !orchestration_result[:error]
          knowledge_context = orchestration_result[:context_for_llm]
          Rails.logger.info "Orchestrator provided #{knowledge_context&.length || 0} chars of context"
          
          # Store metadata about what was found
          if assistant_message = conversation.messages.where(role: 'assistant').last
            assistant_message.metadata.merge!(
              orchestration: {
                tool_used: orchestration_result[:tool_used],
                confidence: orchestration_result[:confidence],
                results_count: orchestration_result[:results][:items]&.size || 0,
                canonical_entities: orchestration_result[:canonical_entities],
                detected_pools: orchestration_result[:detected_pools]
              }
            )
          end
        end
      rescue => e
        Rails.logger.error "QueryOrchestrator failed: #{e.message}"
        # Continue without orchestration context
      end
    end
    
    # Add knowledge context if available
    if knowledge_context
      messages << {
        role: 'system',
        content: "Knowledge Graph Context:\n#{knowledge_context}"
      }
    end
    
    # Add conversation history (last 20 messages)
    conversation.messages.recent(20).reverse.each do |msg|
      next if msg.role == 'system' # Skip system messages in history
      
      messages << {
        role: msg.role,
        content: msg.content
      }
    end
    
    messages
  end
  
  def build_system_prompt(ekn)
    batch = ekn.ingest_batches.last
    
    # Get actual counts from the database
    item_count = batch&.ingest_items&.count || 0
    
    <<~PROMPT
      You are a Knowledge Navigator for the #{ekn.name} dataset.
      
      Dataset Information:
      - EKN: #{ekn.slug}
      - Total Items: #{item_count}
      - Knowledge Graph: Neo4j database with entities and relationships
      
      Your role is to:
      1. Answer questions about the dataset using the knowledge graph
      2. Provide paths and connections between entities
      3. Cite sources and maintain accuracy
      4. Be helpful, clear, and conversational
      
      When answering:
      - Use the knowledge graph context provided in the next system message
      - Reference specific entities by name and type (e.g., "Idea(Radical Inclusion)")
      - Explain connections and relationships between entities
      - If no relevant context is provided, explain what you would need to answer
      - Be conversational but accurate
      - When you cite entities, use the format: EntityType(EntityName)
      
      The Ten Pool Canon entities you'll encounter:
      - Idea: Concepts, principles, philosophies
      - Practical: Methods, processes, techniques
      - Experience: Stories, testimonials, personal accounts
      - Manifest: Physical/digital artifacts, documents
      - Character: People, agents, roles
      - Time: Temporal entities, events, periods
      - Space: Locations, places, geographic entities
      - Lifecycle: States, transitions, progressions
      - Symbolic: Symbols, meanings, representations
      - Relator: Relationships, connections
    PROMPT
  end
  
  def stream_response(conversation, assistant_message, messages)
    # EXACTLY like the OpenAI example - streaming WITH structured outputs works!
    begin
      Rails.logger.info "Starting REAL streaming for conversation #{conversation.id}"
      
      stream = OPENAI.responses.stream(
        model: conversation.ai_model || OpenaiConfig::SettingsManager.model_for(:answer),
        input: messages,
        text: ChatResponse  # This DOES work with streaming!
      )
      
      json_accumulator = ""
      parsed_response = nil
      chunk_count = 0
      
      # Log what we got
      Rails.logger.info "Stream object: #{stream.class.name}"
      
      # Process exactly like the OpenAI example
      event_total = 0
      stream.each do |event|
        event_total += 1
        Rails.logger.info "Event #{event_total} type: #{event.class.name}"
        
        # Try both namespaces since there might be a version difference
        case event
        when OpenAI::Helpers::Streaming::ResponseTextDeltaEvent, OpenAI::Streaming::ResponseTextDeltaEvent
          # The delta IS the JSON being streamed!
          json_accumulator += event.delta
          chunk_count += 1
          
          # Broadcast partial updates by parsing JSON so far
          if chunk_count % 5 == 0  # Every few chunks
            begin
              # Try to extract answer field from partial JSON
              if json_accumulator.include?('"answer":')
                if match = json_accumulator.match(/"answer":\s*"([^"]*)/)
                  partial_answer = match[1]
                    .gsub(/\\n/, "\n")
                    .gsub(/\\"/, '"')
                    .gsub(/\\r/, "\r")
                    .gsub(/\\t/, "\t")
                    .gsub(/\\\\/, "\\")
                  
                  broadcast_streaming_update(conversation, assistant_message, partial_answer)
                end
              end
            rescue => e
              Rails.logger.debug "Partial JSON parse error (expected): #{e.message}"
            end
          end
          
        when OpenAI::Helpers::Streaming::ResponseTextDoneEvent, OpenAI::Streaming::ResponseTextDoneEvent
          Rails.logger.info "ResponseTextDoneEvent received"
          # EXACTLY like the example - the parsed object is here!
          if event.parsed
            parsed_response = event.parsed
            Rails.logger.info "Got parsed: Answer length=#{parsed_response.answer.length}, Confidence=#{parsed_response.confidence}"
          else
            Rails.logger.warn "No parsed object in ResponseTextDoneEvent"
          end
        end
      end
      
      # The example doesn't call get_final_response - just use what we got from events!
      
      if parsed_response
        metadata = {
          confidence: parsed_response.confidence,
          reasoning: parsed_response.reasoning,
          resources_used: parsed_response.resources_used,
          streamed: true,
          chunks_received: chunk_count
        }
        
        finalize_message(conversation, assistant_message, parsed_response.answer, metadata)
      else
        Rails.logger.error "No parsed response! Event total: #{event_total}"
        Rails.logger.error "JSON accumulated: #{json_accumulator[0..500]}..."
        finalize_message(conversation, assistant_message, "Error: Could not parse response")
      end
      
    rescue => e
      Rails.logger.error "Streaming failed: #{e.class} - #{e.message}"
      Rails.logger.error e.backtrace.first(10).join("\n")
      raise
    end
  end
  
  def broadcast_streaming_update(conversation, assistant_message, text)
    # Send incremental update with raw markdown
    Turbo::StreamsChannel.broadcast_update_to(
      "conversation_#{conversation.id}",
      target: "message-#{assistant_message.id}-content",
      html: <<~HTML
        <div class="streaming-message" data-streaming="true" data-markdown="#{CGI.escapeHTML(text)}">
          <div class="prose prose-sm max-w-none">
            #{ApplicationController.helpers.render_markdown(text)}
          </div>
        </div>
      HTML
    )
  end
  
  def handle_structured_response(conversation, assistant_message, parsed, text)
    # Handle structured response with metadata
    metadata_updates = {}
    
    if parsed.respond_to?(:confidence)
      metadata_updates[:confidence] = parsed.confidence
    end
    
    if parsed.respond_to?(:reasoning)
      metadata_updates[:reasoning] = parsed.reasoning
    end
    
    if parsed.respond_to?(:resources_used)
      metadata_updates[:resources_used] = parsed.resources_used
    end
    
    # Use the answer from structured output if available
    final_text = parsed.respond_to?(:answer) ? parsed.answer : text
    
    finalize_message(conversation, assistant_message, final_text, metadata_updates)
  end
  
  def finalize_message(conversation, assistant_message, text, metadata_updates = {})
    # Final update - mark as complete
    assistant_message.update!(
      content: text,
      tokens_used: estimate_tokens(text),
      metadata: assistant_message.metadata.merge(
        completed_at: Time.current,
        streaming: false
      ).merge(metadata_updates)
    )
    
    # Send the complete message with markdown rendering
    Rails.logger.info "Broadcasting final message for conversation #{conversation.id}"
    Turbo::StreamsChannel.broadcast_replace_to(
      "conversation_#{conversation.id}",
      target: "message-#{assistant_message.id}",
      partial: "ekns/chat/message",
      locals: { message: assistant_message, ekn: conversation.ekn }
    )
  end
  
  
  def handle_error(conversation, assistant_message, error)
    Rails.logger.error "Chat response error: #{error.message}"
    Rails.logger.error error.backtrace.join("\n")
    
    # Create or update assistant message with error
    if assistant_message.nil?
      assistant_message = conversation.messages.create!(
        role: 'assistant',
        content: 'Error occurred',
        metadata: {
          error: true,
          error_message: error.message,
          error_class: error.class.name,
          error_backtrace: Rails.env.development? ? error.backtrace.first(10) : nil
        }
      )
    else
      assistant_message.update!(
        content: 'Error occurred',
        metadata: assistant_message.metadata.merge(
          error: true,
          streaming: false,
          error_message: error.message,
          error_class: error.class.name,
          error_backtrace: Rails.env.development? ? error.backtrace.first(10) : nil
        )
      )
    end
    
    # Render error with full details in development
    error_html = render_error_message(error, assistant_message)
    
    Turbo::StreamsChannel.broadcast_replace_to(
      "conversation_#{conversation.id}",
      target: "message-#{assistant_message.id}",
      partial: "ekns/chat/error_message",
      locals: { 
        message: assistant_message,
        error: error,
        show_details: Rails.env.development?
      }
    )
  end
  
  def render_error_message(error, message)
    ekn_name = message.conversation&.ekn&.name || "Unknown EKN"
    error_details = {
      error_class: error.class.name,
      message: error.message,
      ekn: ekn_name,
      message_id: message.id,
      timestamp: Time.current.iso8601,
      backtrace: error.backtrace.first(10)
    }
    
    if Rails.env.development?
      <<~HTML
        <div class="bg-red-50 border border-red-200 rounded-lg p-4" id="error-message-#{message.id}">
          <div class="flex items-start">
            <div class="flex-shrink-0">
              <svg class="h-5 w-5 text-red-400" viewBox="0 0 20 20" fill="currentColor">
                <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd"/>
              </svg>
            </div>
            <div class="ml-3 flex-1">
              <h3 class="text-sm font-medium text-red-800">
                #{ekn_name} • Error
              </h3>
              <div class="mt-1 text-xs text-red-600">
                #{error.class.name}
              </div>
              <div class="mt-2 text-sm text-red-700">
                <p>#{CGI.escapeHTML(error.message)}</p>
              </div>
              <details class="mt-3">
                <summary class="text-sm text-red-600 cursor-pointer hover:text-red-800">
                  Show stack trace
                </summary>
                <pre class="mt-2 text-xs bg-gray-900 text-gray-100 p-2 rounded overflow-x-auto">#{CGI.escapeHTML(error.backtrace.first(10).join("\n"))}</pre>
              </details>
              <div class="mt-4 flex gap-2">
                <button class="text-sm bg-gray-100 hover:bg-gray-200 text-gray-800 px-3 py-1 rounded transition-colors flex items-center gap-1"
                        data-action="click->chat#copyError"
                        data-error-details='#{CGI.escapeHTML(error_details.to_json)}'>
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z"/>
                  </svg>
                  Copy Error
                </button>
                <button class="text-sm bg-red-100 hover:bg-red-200 text-red-800 px-3 py-1 rounded transition-colors"
                        data-action="click->chat#retryMessage"
                        data-message-id="#{message.id}">
                  Retry
                </button>
              </div>
              <div class="mt-2 text-xs text-gray-500">
                Message ID: #{message.id}
              </div>
            </div>
          </div>
        </div>
      HTML
    else
      <<~HTML
        <div class="bg-red-50 border border-red-200 rounded-lg p-4">
          <div class="flex items-start">
            <div class="flex-shrink-0">
              <svg class="h-5 w-5 text-red-400" viewBox="0 0 20 20" fill="currentColor">
                <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd"/>
              </svg>
            </div>
            <div class="ml-3 flex-1">
              <h3 class="text-sm font-medium text-red-800">
                #{ekn_name}
              </h3>
              <p class="text-sm text-red-700 mt-1">
                I encountered an error processing your request. Please try again.
              </p>
              <div class="mt-3">
                <button class="text-sm bg-red-100 hover:bg-red-200 text-red-800 px-3 py-1 rounded transition-colors"
                        data-action="click->chat#retryMessage"
                        data-message-id="#{message.id}">
                  Retry
                </button>
              </div>
            </div>
          </div>
        </div>
      HTML
    end
  end
  
  def estimate_tokens(text)
    # Rough estimate: 1 token ≈ 4 characters
    return 0 if text.nil? || text.empty?
    (text.length / 4.0).ceil
  end
  
  # Removed - now using the MarkdownHelper from ApplicationController
end