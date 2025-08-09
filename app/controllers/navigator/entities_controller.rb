class Navigator::EntitiesController < ApplicationController
  def show
    @id = params[:id]
    
    # Find the current EKN (use first one with data for now)
    ekn = Ekn.joins(:ingest_batches).where(ingest_batches: { status: 'complete' }).first
    
    unless ekn
      render plain: "No EKN with complete data found", status: :not_found
      return
    end
    
    # Initialize services
    navigator = Graph::NavigatorService.new(ekn: ekn)
    manager = Graph::RelationshipManager.new(ekn: ekn)
    
    # Find the node
    @entity = navigator.find_node(@id.to_i)
    
    unless @entity
      render plain: "Entity not found", status: :not_found
      return
    end
    
    # Get edges grouped by canonical verb
    @edges_by_verb = navigator.edges_by_verb_for_entity(@id.to_i)
    
    # Sort verbs by spec order
    verb_order = %w[embodies codifies influences supports validated_by elicits manifests_in 
                    collaborates_with performs_in participates_in organized_by]
    @sorted_verbs = @edges_by_verb.keys.sort_by { |v| verb_order.index(v.to_s) || 999 }
  end
end