# Analyzes user input to determine intent
# This is where we could integrate the fine-tuned model for better intent routing
module Navigator
  class IntentAnalyzer
    INTENT_PATTERNS = {
      greeting: /^(hi|hello|hey|greetings|good\s+(morning|afternoon|evening))/i,
      explain_enliterator: /(what is enliterator|explain enliterator|tell me about enliterator|enliteracy|enliterat|literacy score|knowledge navigator)/i,
      explain_process: /(how does|how do|process|pipeline|stages|works?|explain how)/i,
      show_statistics: /(how many|statistics|stats|count|total|summary)/i,
      search_entities: /(search|find|look for|show me|where is|list)/i,
      create_ekn: /(create|build|make|generate)\s+(ekn|knowledge navigator|navigator)/i,
      explore_data: /(explore|browse|navigate|show data)/i,
      find_connections: /(connect|relation|link|between|path)/i,
      spatial_analysis: /(location|spatial|where|nearby|adjacent)/i,
      help: /(help|what can you do|capabilities|features)/i
    }.freeze
    
    def analyze(text, context = {})
      # Clean and normalize input
      normalized = text.strip.downcase
      
      # Try pattern matching first
      intent_type = detect_intent_by_pattern(normalized)
      
      # Extract entities mentioned
      entities = extract_entities(text)
      
      # Calculate confidence
      confidence = calculate_confidence(intent_type, text, context)
      
      {
        type: intent_type,
        confidence: confidence,
        entities: entities,
        original_text: text,
        context: context
      }
    end
    
    private
    
    def detect_intent_by_pattern(text)
      INTENT_PATTERNS.each do |intent, pattern|
        return intent if text.match?(pattern)
      end
      
      :general_query
    end
    
    def extract_entities(text)
      # Basic entity extraction - would be enhanced with NER model
      entities = []
      
      # Look for quoted strings
      text.scan(/"([^"]+)"/).each do |match|
        entities << { text: match[0], type: :quoted }
      end
      
      # Look for capitalized words (potential proper nouns)
      text.scan(/\b[A-Z][a-z]+\b/).each do |word|
        entities << { text: word, type: :proper_noun }
      end
      
      entities
    end
    
    def calculate_confidence(intent_type, text, context)
      # Basic confidence calculation
      return 0.9 if intent_type != :general_query
      
      # Check context for clues
      return 0.7 if context[:history]&.any?
      
      0.5
    end
  end
end