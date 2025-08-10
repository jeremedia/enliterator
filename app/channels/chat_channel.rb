class ChatChannel < ApplicationCable::Channel
  def subscribed
    conversation = Conversation.find(params[:conversation_id])
    stream_for conversation
    
    # Send connection confirmation
    transmit(type: 'connected', conversation_id: conversation.id)
  end

  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
  end

  def send_message(data)
    conversation = Conversation.find(data['conversation_id'])
    
    # Add user message
    user_message = conversation.add_message(
      role: 'user',
      content: data['message'],
      metadata: {
        client_id: data['client_id'],
        timestamp: Time.current
      }
    )
    
    # Broadcast the user message immediately
    ChatChannel.broadcast_to(
      conversation,
      type: 'message',
      message: format_message(user_message)
    )
    
    # Start processing the AI response
    ChatStreamingJob.perform_later(
      conversation_id: conversation.id,
      message_id: user_message.id
    )
  end
  
  def typing_indicator(data)
    conversation = Conversation.find(data['conversation_id'])
    
    # Broadcast typing indicator to other clients
    ChatChannel.broadcast_to(
      conversation,
      type: 'typing',
      user: data['user'] || 'User',
      is_typing: data['is_typing']
    )
  end
  
  def regenerate_response(data)
    conversation = Conversation.find(data['conversation_id'])
    message = conversation.messages.find(data['message_id'])
    
    # Mark the assistant message for regeneration
    ChatStreamingJob.perform_later(
      conversation_id: conversation.id,
      message_id: message.id,
      regenerate: true
    )
  end
  
  private
  
  def format_message(message)
    {
      id: message.id,
      role: message.role,
      content: message.content,
      metadata: message.metadata,
      created_at: message.created_at.iso8601
    }
  end
end