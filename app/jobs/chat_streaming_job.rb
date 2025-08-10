class ChatStreamingJob < ApplicationJob
  queue_as :default
  
  def perform(conversation_id:, message_id:, regenerate: false)
    conversation = Conversation.find(conversation_id)
    user_message = conversation.messages.find(message_id)
    
    # Broadcast typing indicator
    ChatChannel.broadcast_to(
      conversation,
      type: 'typing_indicator',
      role: 'assistant',
      is_typing: true
    )
    
    # Create assistant message placeholder
    assistant_message = conversation.add_message(
      role: 'assistant',
      content: '',
      metadata: {
        streaming: true,
        model_used: conversation.ai_model,
        started_at: Time.current
      }
    )
    
    # Broadcast message created event
    ChatChannel.broadcast_to(
      conversation,
      type: 'message_start',
      message: {
        id: assistant_message.id,
        role: 'assistant',
        content: '',
        created_at: assistant_message.created_at.iso8601
      }
    )
    
    # Build messages for OpenAI
    messages = build_messages_for_openai(conversation)
    
    # Stream response from OpenAI
    stream_response(conversation, assistant_message, messages)
    
  rescue => e
    handle_error(conversation, assistant_message, e)
  ensure
    # Stop typing indicator
    ChatChannel.broadcast_to(
      conversation,
      type: 'typing_indicator',
      role: 'assistant',
      is_typing: false
    )
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
    <<~PROMPT
      You are a Knowledge Navigator for the #{ekn.name} dataset.
      
      Dataset Information:
      - Total Nodes: #{ekn.ingest_batches.last&.pool_items&.count || 0}
      - Lexicon Terms: #{ekn.ingest_batches.last&.lexicon_entries&.count || 0}
      - Knowledge Graph: Neo4j database with entities and relationships
      
      Your role is to:
      1. Answer questions about the dataset using the knowledge graph
      2. Provide paths and connections between entities
      3. Cite sources and maintain accuracy
      4. Be helpful, clear, and conversational
      
      When answering:
      - Use the knowledge graph to find connections
      - Provide specific entity names and relationships
      - Cite your sources when possible
      - Explain your reasoning
      - Be conversational but accurate
    PROMPT
  end
  
  def stream_response(conversation, assistant_message, messages)
    client = OpenAI::Client.new(
      access_token: ENV.fetch('OPENAI_API_KEY'),
      log_errors: true
    )
    
    full_response = ""
    token_count = 0
    
    client.chat(
      parameters: {
        model: conversation.ai_model,
        messages: messages,
        temperature: conversation.temperature || 0.7,
        max_tokens: conversation.max_tokens || 2000,
        stream: proc do |chunk, _bytesize|
          handle_stream_chunk(chunk, conversation, assistant_message, full_response, token_count)
        end
      }
    )
    
    # Final update with complete message
    assistant_message.update!(
      content: full_response,
      tokens_used: token_count,
      metadata: assistant_message.metadata.merge(
        completed_at: Time.current,
        streaming: false
      )
    )
    
    # Broadcast completion
    ChatChannel.broadcast_to(
      conversation,
      type: 'message_complete',
      message: {
        id: assistant_message.id,
        content: full_response,
        tokens_used: token_count
      }
    )
  end
  
  def handle_stream_chunk(chunk, conversation, assistant_message, full_response, token_count)
    return unless chunk.dig("choices", 0, "delta", "content")
    
    content = chunk.dig("choices", 0, "delta", "content")
    full_response << content
    token_count += 1 # Rough estimate
    
    # Broadcast the chunk
    ChatChannel.broadcast_to(
      conversation,
      type: 'message_chunk',
      message: {
        id: assistant_message.id,
        chunk: content
      }
    )
    
    # Periodically save to database (every 50 tokens)
    if token_count % 50 == 0
      assistant_message.update_column(:content, full_response)
    end
  end
  
  def handle_error(conversation, assistant_message, error)
    Rails.logger.error "Chat streaming error: #{error.message}"
    Rails.logger.error error.backtrace.join("\n")
    
    error_message = case error
    when OpenAI::Error
      "I encountered an error while processing your request. Please try again."
    when ActiveRecord::RecordNotFound
      "I couldn't find the conversation or message. Please refresh and try again."
    else
      "An unexpected error occurred. Please try again."
    end
    
    # Update message with error
    if assistant_message
      assistant_message.update!(
        content: error_message,
        metadata: assistant_message.metadata.merge(
          error: true,
          error_message: error.message,
          error_class: error.class.name
        )
      )
    end
    
    # Broadcast error
    ChatChannel.broadcast_to(
      conversation,
      type: 'error',
      message: {
        id: assistant_message&.id,
        error: error_message
      }
    )
  end
end