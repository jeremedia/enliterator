# Orchestrates the full conversational experience with visualizations
# This is the conductor that brings together language, data, and visual presentation
module Navigator
  class ConversationOrchestrator
    attr_reader :ekn, :context
    
    def initialize(ekn:, context: {})
      @ekn = ekn
      @context = context
      @conversation_manager = ConversationManager.new(context: context, ekn: ekn)
      @visualization_generator = VisualizationGenerator.new(ekn: ekn)
      @visualization_recognizer = VisualizationIntentRecognizer.new
    end
    
    def process(message, ekn_slug)
      # Find EKN by slug (friendly_id makes this work with slug or ID)
      ekn = Ekn.find(ekn_slug)
      
      # Check for visualization intent FIRST (before other processing)
      viz_intent = @visualization_recognizer.recognize(message)
      should_viz = @visualization_recognizer.should_visualize?(message, @context)
      
      # Process the message through conversation manager
      base_response = @conversation_manager.process_input(message, @context)
      
      # Generate visualization if needed
      visualization = nil
      if viz_intent || should_viz
        visualization = @visualization_generator.generate_for_query(
          message, 
          @context.merge(entities: extract_entities_from_response(base_response))
        )
      end
      
      # Enhance response with visualization
      response = base_response.merge(
        visualization: visualization,
        ekn_info: {
          id: ekn.id,
          slug: ekn.slug,
          name: ekn.name,
          total_nodes: ekn.total_nodes,
          total_relationships: ekn.total_relationships,
          literacy_score: ekn.literacy_score
        }
      )
      
      # Add visualization-aware suggestions if we generated a viz
      if visualization
        response[:suggestions] = enhance_suggestions_with_viz(
          response[:suggestions] || [],
          visualization[:type]
        )
      end
      
      response
    end
    
    private
    
    def extract_entities_from_response(response)
      # Extract entities mentioned in the response for context
      entities = []
      
      # Check if search results are present
      if response.dig(:metadata, :operations_performed)&.include?('SearchEntitiesOperation')
        # Extract entities from search results if available
        # This would be enhanced with actual entity extraction
        entities = []
      end
      
      entities
    end
    
    def enhance_suggestions_with_viz(base_suggestions, viz_type)
      viz_suggestions = case viz_type
      when 'relationship_graph'
        [
          "Show me more connections from this node",
          "What paths connect these entities?",
          "Expand the network view"
        ]
      when 'timeline'
        [
          "Show earlier events",
          "What happened next?",
          "Zoom in on this time period"
        ]
      when 'comparison_chart'
        [
          "Add another item to compare",
          "Show different metrics",
          "Export this comparison"
        ]
      else
        []
      end
      
      # Combine with base suggestions, limiting total
      (viz_suggestions + base_suggestions).uniq.first(5)
    end
  end
end