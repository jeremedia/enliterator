module Ekns
  class ChatController < ApplicationController
    before_action :load_ekn
    before_action :load_conversation, only: [:show, :messages, :send_message]
    
    def index
      @conversations = @ekn.conversations
        .includes(:messages)
        .order(last_activity_at: :desc)
        .limit(20)
    end
    
    def show
      @messages = @conversation.messages
        .includes(:prompt_version)
        .order(:created_at)
      
      @conversation.update!(status: :active, last_activity_at: Time.current)
    end
    
    def new
      @conversation = @ekn.conversations.create!(
        status: :active,
        last_activity_at: Time.current,
        context: {
          started_at: Time.current,
          initial_mode: params[:mode] || 'chat'
        },
        model_config: {
          model_name: OpenaiConfig::SettingsManager.model_for(:answer),
          temperature: 0.7,
          max_tokens: 2000,
          use_mcp_tools: true  # ALWAYS ENABLE MCP TOOLS
        }
      )
      
      redirect_to chat_path(ekn_slug: @ekn.slug, id: @conversation)
    end
    
    def messages
      @messages = @conversation.messages
        .includes(:prompt_version)
        .order(:created_at)
      
      render partial: 'messages', locals: { messages: @messages }
    end
    
    def send_message
      # Add user message
      @user_message = @conversation.add_message(
        role: 'user',
        content: params[:message],
        metadata: {
          client_id: params[:client_id],
          timestamp: Time.current
        }
      )
      
      # Render the user message immediately via Turbo Stream
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.append("messages", partial: "ekns/chat/message", locals: { message: @user_message }),
            turbo_stream.replace("message-form", partial: "ekns/chat/message_form", locals: { conversation: @conversation, ekn: @ekn }),
            turbo_stream.update("typing-indicator", partial: "ekns/chat/typing_indicator", locals: { show: true })
          ]
        end
      end


      #log if mcp tools are enabled
      if @conversation.model_config&.dig('use_mcp_tools') || params[:use_mcp] == 'true'
        Rails.logger.info "MCP tools enabled for conversation #{@conversation.id}"
      else
        Rails.logger.info "MCP tools not enabled for conversation #{@conversation.id}"
      end
      # Process AI response in background
      # Use MCP-enabled job if configured
      if @conversation.model_config&.dig('use_mcp_tools') || params[:use_mcp] == 'true'
        Rails.logger.info "Using ChatResponseWithMcpJob for conversation #{@conversation.id}"
        ChatResponseWithMcpJob.perform_later(
          conversation_id: @conversation.id,
          message_id: @user_message.id
        )
      else
        Rails.logger.info "Using regular ChatResponseJob for conversation #{@conversation.id}"
        ChatResponseJob.perform_later(
          conversation_id: @conversation.id,
          message_id: @user_message.id
        )
      end
    end
    
    def update_settings
      @conversation = @ekn.conversations.find(params[:conversation_id])
      
      if @conversation.update(conversation_params)
        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: turbo_stream.replace(
              "settings-panel",
              partial: "ekns/chat/settings",
              locals: { conversation: @conversation }
            )
          end
          format.json { render json: { success: true, settings: @conversation.model_configuration } }
        end
      else
        render json: { success: false, errors: @conversation.errors.full_messages }
      end
    end
    
    def retry
      message = Message.find(params[:message_id])
      @conversation = message.conversation
      
      # Find the last user message before this error
      last_user_message = @conversation.messages
        .where(role: 'user')
        .where('created_at < ?', message.created_at)
        .order(created_at: :desc)
        .first
      
      if last_user_message
        # Delete the error message
        message.destroy
        
        # Re-enqueue the job with the last user message
        ChatResponseJob.perform_later(
          conversation_id: @conversation.id,
          message_id: last_user_message.id
        )
        
        redirect_to chat_path(ekn_slug: @ekn.slug, id: @conversation), 
                    notice: "Retrying message..."
      else
        redirect_to chat_path(ekn_slug: @ekn.slug, id: @conversation), 
                    alert: "Could not find message to retry"
      end
    end
    
    private
    
    def load_ekn
      @ekn = ::Ekn.find_by!(slug: params[:ekn_slug])
    end
    
    def load_conversation
      @conversation = @ekn.conversations.find(params[:id])
    end
    
    def conversation_params
      params.require(:conversation).permit(
        :expertise_level,
        model_config: [:model_name, :temperature, :max_tokens, :top_p]
      )
    end
  end
end