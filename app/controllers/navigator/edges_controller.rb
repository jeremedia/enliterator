class Navigator::EdgesController < ApplicationController
  skip_before_action :verify_authenticity_token # For AJAX calls
  
  def promote
    ekn = Ekn.joins(:ingest_batches).where(ingest_batches: { status: 'complete' }).first
    
    unless ekn
      render json: { error: "No EKN found" }, status: :not_found
      return
    end
    
    manager = Graph::RelationshipManager.new(ekn: ekn)
    edge_id = params[:id].to_i
    
    # Promote with rights check (handled internally by manager)
    success = manager.promote_to_verified(
      edge_id, 
      promoted_by: current_user&.email || 'system',
      reason: params[:reason] || 'Manual curation'
    )
    
    if success
      render json: { status: 'success', message: 'Edge promoted to verified' }
    else
      render json: { status: 'error', message: 'Failed to promote edge (may be rights issue)' }, status: :unprocessable_entity
    end
  end

  def reject
    ekn = Ekn.joins(:ingest_batches).where(ingest_batches: { status: 'complete' }).first
    
    unless ekn
      render json: { error: "No EKN found" }, status: :not_found
      return
    end
    
    manager = Graph::RelationshipManager.new(ekn: ekn)
    edge_id = params[:id].to_i
    
    success = manager.reject_candidate(
      edge_id,
      rejected_by: current_user&.email || 'system',
      reason: params[:reason] || 'Manual curation'
    )
    
    if success
      render json: { status: 'success', message: 'Edge rejected' }
    else
      render json: { status: 'error', message: 'Failed to reject edge' }, status: :unprocessable_entity
    end
  end
end