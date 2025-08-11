module Admin
  class McpToolCallsController < ApplicationController
    before_action :set_mcp_tool_call, only: [:show]
    
    def index
      @mcp_tool_calls = McpToolCall.recent.includes(:ekn, :conversation, :message, :logs)
      @mcp_tool_calls = @mcp_tool_calls.page(params[:page]).per(50)
      
      # Stats for dashboard
      @stats = {
        total: McpToolCall.count,
        completed: McpToolCall.completed.count,
        failed: McpToolCall.failed.count,
        pending: McpToolCall.pending.count,
        avg_duration: McpToolCall.completed.average('completed_at - started_at')&.to_f&.round(2)
      }
    end
    
    def show
      @logs = @mcp_tool_call.logs.includes(:log_items)
    end
    
    def recent
      @mcp_tool_calls = McpToolCall.recent.limit(10)
      render partial: 'recent_calls'
    end
    
    def failed
      @mcp_tool_calls = McpToolCall.failed.recent.limit(20)
      render :index
    end
    
    private
    
    def set_mcp_tool_call
      @mcp_tool_call = McpToolCall.find(params[:id])
    end
  end
end