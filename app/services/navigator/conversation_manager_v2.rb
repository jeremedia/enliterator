# Version 2: The REAL conversation manager that uses the fine-tuned model
# No more puppet strings - the model navigates the knowledge
module Navigator
  class ConversationManagerV2
    attr_reader :ekn
    
    def initialize(context:, ekn: nil)
      @context = context
      @ekn = ekn
      # Use StructuredNavigator with proper OpenAI Responses API
      @model_navigator = StructuredNavigator.new(ekn: ekn) if ekn
    end
    
    def process_input(user_text, conversation_context = {})
      return fallback_response unless @model_navigator
      
      # Let the trained model navigate the knowledge
      navigation_result = @model_navigator.navigate(user_text)
      
      # Build suggestions based on what was explored
      suggestions = generate_suggestions(navigation_result)
      
      {
        message: navigation_result[:message],
        suggestions: suggestions,
        metadata: {
          sources: navigation_result[:sources],
          confidence: navigation_result[:confidence],
          paths_explored: navigation_result[:paths_explored]&.size || 0,
          model: "fine-tuned-navigator"
        }
      }
    rescue StandardError => e
      Rails.logger.error "ConversationManagerV2 error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      fallback_response
    end
    
    private
    
    def generate_suggestions(result)
      # Generate contextual suggestions based on what was found
      suggestions = []
      
      if result[:paths_explored]&.any?
        suggestions << "Tell me more about these connections"
        suggestions << "What else relates to this?"
      end
      
      if result[:sources]&.include?("Graph search")
        suggestions << "Show me similar concepts"
        suggestions << "How do these ideas connect?"
      end
      
      # Always include some exploratory options
      suggestions << "Explain the Ten Pool Canon"
      suggestions << "What patterns do you see?"
      
      suggestions.first(4)
    end
    
    def fallback_response
      {
        message: "I need a Knowledge Navigator (EKN) to explore. Please load a dataset first.",
        suggestions: [
          "Create a Knowledge Navigator",
          "What is Enliterator?",
          "How does this work?"
        ]
      }
    end
  end
end