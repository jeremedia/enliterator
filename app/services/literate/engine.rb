# app/services/literate/engine.rb
# The Knowledge Navigator Engine - Makes Enliterator truly literate
module Literate
  class Engine
    attr_reader :conversation, :context_builder, :interpreter, :executor
    
    def initialize(conversation = nil)
      @conversation = conversation || Conversation.create
      @context_builder = ContextBuilder.new(@conversation)
      @interpreter = IntentInterpreter.new
      @executor = ActionExecutor.new(@conversation)
      @knowledge_graph = KnowledgeInterface.new(@conversation)
    end
    
    # Process natural language input and respond literately
    def process(user_input)
      # Record user message
      user_message = @conversation.add_message(
        role: 'user',
        content: user_input
      )
      
      # Build rich context
      context = @context_builder.build
      
      # The literate app can adjust its own parameters
      adjust_model_for_context(user_input, context)
      
      # Interpret intent using current model config
      intent = @interpreter.interpret(
        user_input, 
        context,
        @conversation.model_configuration
      )
      
      # Record interpreted intent
      user_message.update!(metadata: { intent: intent.to_h })
      
      # Execute actions if needed
      results = nil
      if intent.executable?
        results = @executor.execute(intent)
      end
      
      # Generate literate response
      response = generate_literate_response(intent, results, context)
      
      # Record assistant message with full metadata
      assistant_message = @conversation.add_message(
        role: 'assistant',
        content: response[:content],
        metadata: {
          intent: intent.primary_intent,
          model_used: @conversation.ai_model,
          temperature_used: @conversation.temperature,
          confidence_score: response[:confidence],
          reasoning_trace: response[:reasoning],
          actions_taken: results&.map { |r| r[:action] }
        }
      )
      
      # Return the response
      response[:content]
    end
    
    # Generate a truly literate response
    def generate_literate_response(intent, results, context)
      # Select appropriate prompt based on intent
      prompt = select_prompt(intent, context)
      
      # Build the system message
      system_message = build_system_message(prompt, context)
      
      # Build the user message for response generation
      user_message = build_response_request(intent, results, context)
      
      # Call OpenAI with conversation's model config
      begin
        response = OPENAI.chat.completions.create(
          **@conversation.model_configuration,
          messages: [
            { role: "system", content: system_message },
            { role: "user", content: user_message }
          ]
        )
        
        content = response.dig("choices", 0, "message", "content")
        confidence = calculate_confidence(response)
        
        {
          content: content,
          confidence: confidence,
          reasoning: extract_reasoning(response),
          model_response: response
        }
        
      rescue => e
        handle_api_error(e, intent)
      end
    end
    
    private
    
    # The literate app adjusts its own model configuration
    def adjust_model_for_context(input, context)
      # Detect if we need high precision
      if input.match?(/exact|specific|precisely|database|SQL/i)
        @conversation.update!(
          temperature: 0.1,
          model_name: "gpt-4o"
        )
        
      # Detect if we need creativity
      elsif input.match?(/idea|suggest|create|imagine|what if/i)
        @conversation.update!(
          temperature: 0.9,
          model_name: "gpt-4o"
        )
        
      # Detect if we need structured data
      elsif input.match?(/extract|parse|structure|organize/i)
        @conversation.configure_for_intent(:extraction)
        
      # Default conversational mode
      else
        @conversation.configure_for_intent(:conversation)
      end
    end
    
    def select_prompt(intent, context)
      # Find the best prompt for this intent
      prompt = Prompt.active
                    .by_category(intent.category)
                    .by_context(context[:current_stage] || :global)
                    .first
      
      # Fallback to general prompt
      prompt ||= Prompt.find_by(key: 'general_response')
      
      # Get the active version (or create default)
      prompt&.active_version
    end
    
    def build_system_message(prompt_version, context)
      # Base system message
      base = if prompt_version
        prompt_version.render(context)
      else
        default_system_prompt
      end
      
      # Add Knowledge Navigator identity
      navigator_identity = <<~IDENTITY
        
        You are a Knowledge Navigator - an intelligent interface that helps users
        understand and work with data. You can:
        - Understand natural language and context
        - Navigate complex knowledge spaces
        - Execute operations while explaining them
        - Learn and adapt from interactions
        - Create other Knowledge Navigators from data
        
        Current context:
        - Dataset: #{context[:current_dataset] || 'None selected'}
        - Stage: #{context[:current_stage] || 'Ready'}
        - User expertise: #{context[:user_expertise] || 'intermediate'}
      IDENTITY
      
      base + navigator_identity
    end
    
    def build_response_request(intent, results, context)
      request = "User intent: #{intent.description}\n\n"
      
      if results.present?
        request += "Actions taken:\n"
        results.each do |result|
          request += "- #{result[:explanation]}\n"
          request += "  Result: #{result[:outcome]}\n"
        end
        request += "\n"
      end
      
      request += "Please provide a literate response that:\n"
      request += "1. Acknowledges what was understood\n"
      request += "2. Explains what was done (if anything)\n"
      request += "3. Provides insights or next steps\n"
      request += "4. Maintains conversation continuity\n"
      
      request
    end
    
    def default_system_prompt
      <<~PROMPT
        You are Enliterator's Knowledge Navigator. You help users transform
        data into knowledge through natural conversation. You understand context,
        explain your reasoning, and can execute operations while maintaining
        a helpful, literate dialogue.
      PROMPT
    end
    
    def calculate_confidence(response)
      # Extract confidence from log probabilities if available
      # For now, return a default
      0.85
    end
    
    def extract_reasoning(response)
      # Extract reasoning trace if model provides it
      # Could parse from response or use specific markers
      nil
    end
    
    def handle_api_error(error, intent)
      {
        content: "I encountered an issue while processing your request: #{error.message}. " \
                 "Let me try a different approach.",
        confidence: 0.0,
        reasoning: "API error: #{error.class}",
        error: error
      }
    end
  end
  
  # Builds rich context for literate responses
  class ContextBuilder
    def initialize(conversation)
      @conversation = conversation
    end
    
    def build
      context = @conversation.build_context
      
      # Add current pipeline status
      if @conversation.ingest_batch
        context[:pipeline_status] = @conversation.ingest_batch.status
        context[:pipeline_stage] = detect_current_stage
      end
      
      # Add knowledge graph context if available
      if @conversation.current_dataset
        context[:graph_stats] = fetch_graph_statistics
        context[:available_pools] = fetch_available_pools
      end
      
      # Add user history and preferences
      if @conversation.user
        context[:user_history] = fetch_user_history
        context[:user_preferences] = fetch_user_preferences
      end
      
      context
    end
    
    private
    
    def detect_current_stage
      # Detect which pipeline stage we're in
      batch = @conversation.ingest_batch
      return nil unless batch
      
      case batch.status
      when 'ingesting' then :intake
      when 'processing_rights' then :rights
      when 'building_lexicon' then :lexicon
      when 'extracting_pools' then :pools
      when 'building_graph' then :graph
      when 'generating_embeddings' then :embeddings
      when 'scoring_literacy' then :literacy
      when 'generating_deliverables' then :deliverables
      else :ready
      end
    end
    
    def fetch_graph_statistics
      # Fetch stats from Neo4j if available
      {
        node_count: 0,  # Would query Neo4j
        edge_count: 0,
        pools_populated: []
      }
    end
    
    def fetch_available_pools
      # List which pools have data
      []
    end
    
    def fetch_user_history
      # Get user's recent interactions
      @conversation.user.conversations.recent.limit(5).map(&:summary)
    rescue
      []
    end
    
    def fetch_user_preferences
      # Get user's preferences
      {}
    end
  end
end