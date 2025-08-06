# Handles the conversational interaction between users and their Knowledge Navigators
# This is where natural language becomes action - the heart of the literate interface
module Navigator
  class ConversationController < ApplicationController
    skip_before_action :verify_authenticity_token, only: [:converse]
    before_action :set_conversation_context
    
    def index
      # Renders the conversation interface
      @conversation_id = session[:conversation_id] ||= SecureRandom.uuid
      @messages = ConversationHistory.for_conversation(@conversation_id)
                                     .limit(20)
                                     .map { |h| { role: h.role, content: h.content, timestamp: h.created_at.iso8601 } }
      @ekn = current_ekn
    end
    
    def converse
      # Process user input and generate natural response
      # This is where we transform technical operations into conversation
      
      user_input = params[:message]
      return render_error("Please provide a message") if user_input.blank?
      
      # Add user message to history
      add_to_conversation("user", user_input)
      
      # Process through the conversation manager
      response = conversation_manager.process_input(user_input, @conversation_context)
      
      # Add assistant response to history  
      add_to_conversation("assistant", response[:message])
      
      # Check if UI generation is needed
      ui_spec = response[:ui_spec]
      
      # Check if visualization was generated
      visualization = response[:visualization]
      
      # Check if voice synthesis is requested
      voice_url = synthesize_voice(response[:message]) if params[:voice_enabled]
      
      render json: {
        message: response[:message],
        ui_spec: ui_spec,
        visualization: visualization,
        voice_url: voice_url,
        conversation_id: @conversation_id,
        suggestions: response[:suggestions] # Suggested follow-up questions
      }
    rescue StandardError => e
      Rails.logger.error "Conversation error: #{e.message}"
      render_error("I encountered an issue understanding that. Could you rephrase?")
    end
    
    private
    
    def set_conversation_context
      @conversation_id = session[:conversation_id] ||= SecureRandom.uuid
      @conversation_context = {
        id: @conversation_id,
        history: load_conversation_history,
        current_ekn_id: session[:current_ekn_id],
        user_preferences: user_preferences,
        timestamp: Time.current
      }
    end
    
    def load_conversation_history
      ConversationHistory.for_conversation(@conversation_id)
                         .limit(10)
                         .map { |h| { role: h.role, content: h.content, timestamp: h.created_at.iso8601 } }
    end
    
    def conversation_manager
      # Use V2 with the fine-tuned model if available
      @conversation_manager ||= if ENV['USE_FINETUNED_MODEL'] != 'false'
        Navigator::ConversationManagerV2.new(
          context: @conversation_context,
          ekn: current_ekn
        )
      else
        Navigator::ConversationManager.new(
          context: @conversation_context,
          ekn: current_ekn
        )
      end
    end
    
    def add_to_conversation(role, content)
      # Store in database instead of session to avoid cookie overflow
      ConversationHistory.create!(
        conversation_id: @conversation_id,
        role: role,
        content: content,
        metadata: { 
          ekn_id: session[:current_ekn_id],
          user_preferences: user_preferences 
        }
      )
      
      # Clean up old messages if too many (keep last 100 per conversation)
      excess_count = ConversationHistory.where(conversation_id: @conversation_id).count - 100
      if excess_count > 0
        ConversationHistory.where(conversation_id: @conversation_id)
                          .order(:position)
                          .limit(excess_count)
                          .destroy_all
      end
    end
    
    def current_ekn
      @current_ekn ||= if session[:current_ekn_id]
        IngestBatch.find_by(id: session[:current_ekn_id])
      else
        # Use the Meta-EKN by default
        IngestBatch.where(status: 'completed')
                   .where.not(literacy_score: nil)
                   .order(literacy_score: :desc)
                   .first
      end
    end
    
    def user_preferences
      {
        voice_enabled: params[:voice_enabled] == "true",
        ui_complexity: params[:ui_complexity] || "auto",
        language: params[:language] || "en",
        expertise_level: session[:expertise_level] || "beginner"
      }
    end
    
    def synthesize_voice(text)
      # Integrate with text-to-speech service
      # For now, return nil - will implement with Web Speech API
      nil
    end
    
    def render_error(message)
      render json: {
        error: true,
        message: message,
        conversation_id: @conversation_id
      }, status: :unprocessable_entity
    end
  end
end