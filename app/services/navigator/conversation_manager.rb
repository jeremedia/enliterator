# The brain of the Knowledge Navigator - processes natural language and orchestrates responses
# This service transforms user intent into action while maintaining conversational flow
module Navigator
  class ConversationManager
    attr_reader :context, :ekn
    
    def initialize(context:, ekn: nil)
      @context = context
      @ekn = ekn
      @intent_analyzer = IntentAnalyzer.new
      @response_generator = ResponseGenerator.new
      # UI mapper will be added when UI module is complete
      @ui_mapper = nil # UI::NaturalLanguageMapper.new(ekn) if ekn
    end
    
    def process_input(user_text, conversation_context = {})
      # This is where natural language becomes action
      # We understand, we process, we respond naturally
      
      # 1. Understand the intent
      intent = analyze_intent(user_text, conversation_context)
      
      # 2. Determine what technical operations are needed (using routing model internally)
      operations = determine_operations(intent, user_text)
      
      # 3. Execute operations and gather results
      results = execute_operations(operations)
      
      # 4. Generate natural language response (NOT JSON!)
      response_text = generate_response(intent, results, user_text)
      
      # 5. Determine if UI generation is needed
      ui_spec = generate_ui_if_needed(intent, results)
      
      # 6. Suggest follow-up questions
      suggestions = generate_suggestions(intent, results)
      
      {
        message: response_text,
        ui_spec: ui_spec,
        suggestions: suggestions,
        metadata: {
          intent: intent[:type],
          confidence: intent[:confidence],
          operations_performed: operations.map(&:class).map(&:name)
        }
      }
    rescue StandardError => e
      Rails.logger.error "ConversationManager error: #{e.message}\n#{e.backtrace.first(10).join("\n")}"
      {
        message: "I'm having trouble understanding that. Could you tell me more about what you're looking for? (Error: #{e.message})",
        suggestions: default_suggestions
      }
    end
    
    private
    
    def analyze_intent(user_text, context)
      # Analyze what the user wants to do
      @intent_analyzer.analyze(user_text, context)
    end
    
    def determine_operations(intent, user_text)
      operations = []
      
      case intent[:type]
      when :show_statistics
        operations << ShowStatisticsOperation.new(@ekn)
      when :search_entities
        query = extract_search_query(user_text)
        operations << SearchEntitiesOperation.new(@ekn, query)
      when :explain_enliterator, :explain_process
        operations << ExplainEnliteratorOperation.new(user_text)
      else
        operations << DefaultOperation.new(user_text)
      end
      
      operations
    end
    
    def execute_operations(operations)
      results = {}
      
      operations.each do |operation|
        result = operation.execute
        # Use simple class name without module prefix for results key
        class_name = operation.class.name.split('::').last
        results[class_name] = result
      end
      
      results
    end
    
    def generate_response(intent, results, user_text)
      @response_generator.generate(intent, results, user_text)
    end
    
    def generate_ui_if_needed(intent, results)
      return nil unless should_generate_ui?(intent)
      return nil unless @ui_mapper
      
      @ui_mapper.process(
        intent: intent,
        results: results,
        context: @context
      )
    end
    
    def should_generate_ui?(intent)
      ui_generating_intents = [
        :show_evolution,
        :find_connections, 
        :spatial_analysis,
        :explore_data,
        :show_timeline,
        :compare_data,
        :visualize_patterns
      ]
      
      ui_generating_intents.include?(intent[:type])
    end
    
    def extract_search_query(text)
      # Extract the search query from phrases like "search for X" or "find Y"
      text.gsub(/^(search|find|look for)\s+(for\s+)?/i, '').strip
    end
    
    def generate_suggestions(intent, results)
      @response_generator.generate_suggestions(intent, results)
    end
    
    def default_suggestions
      [
        "How many nodes are in the graph?",
        "What is Enliterator?",
        "Search for models",
        "Show me the Ideas",
        "What can you do?"
      ]
    end
  end
  
  # These are the operation classes used by the manager
  class ExplainEnliteratorOperation
    def initialize(user_text)
      @user_text = user_text.downcase
    end
    
    def execute
      topic = if @user_text.include?('enliteracy') || @user_text.include?('literacy')
        :enliteracy_process
      else
        :general_overview
      end
      
      {
        success: true,
        topic: topic,
        explanation: generate_explanation(topic)
      }
    end
    
    private
    
    def generate_explanation(topic)
      case topic
      when :enliteracy_process
        "Enliteracy is the process that makes a dataset 'literate' - able to converse naturally about its contents. " +
        "It transforms raw data into a knowledge graph with semantic understanding, identifying entities and relationships across 10 pools of meaning. " +
        "The literacy score (0-100) measures how well the system can answer questions. A score of 70+ means the dataset can reliably engage in natural conversation. " +
        "This Meta-EKN has a literacy score of 75, meaning it understands Enliterator's codebase well enough for meaningful dialogue."
      else
        "Enliterator transforms datasets into Knowledge Navigators through a 9-stage pipeline. " +
        "It ingests documents, extracts structured knowledge, builds a graph of relationships, and creates this conversational interface. " +
        "You're experiencing the result right now - a natural language interface to complex data."
      end
    end
  end
  
  class ShowStatisticsOperation
    def initialize(ekn)
      @ekn = ekn
    end
    
    def execute
      return { error: "No EKN available" } unless @ekn
      
      graph_service = Graph::QueryService.new(@ekn.id)
      stats = graph_service.get_statistics
      
      {
        data: stats,
        ekn_name: @ekn.name,
        literacy_score: @ekn.literacy_score
      }
    # Don't close singleton connection
    end
  end
  
  class SearchEntitiesOperation
    def initialize(ekn, query)
      @ekn = ekn
      @query = query
    end
    
    def execute
      return { error: "No EKN available" } unless @ekn
      
      graph_service = Graph::QueryService.new(@ekn.id)
      results = graph_service.search_entities(@query, limit: 10)
      
      {
        query: @query,
        results: results,
        count: results.size
      }
    # Don't close singleton connection
    end
  end
  
  class DefaultOperation
    def initialize(user_text)
      @user_text = user_text
    end
    
    def execute
      { fallback: true, original_text: @user_text }
    end
  end
end