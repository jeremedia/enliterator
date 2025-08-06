# Navigator using structured outputs with the Responses API
module Navigator
  # Response model for navigation results
  class NavigationResponse < OpenAI::Helpers::StructuredOutput::BaseModel
    required :message, String
    required :confidence, Float
    required :entities_found, OpenAI::ArrayOf[String]
    required :paths_explored, Integer
    required :grounded_facts, OpenAI::ArrayOf[String]
    required :suggestions, OpenAI::ArrayOf[String]
  end
  
  class StructuredNavigator
    def initialize(ekn:)
      @ekn = ekn
      @client = OPENAI
      # IMPORTANT: Using nil for batch_id because Neo4j nodes don't have batch_id properties
      # The graph has 280k+ nodes but they're not filtered by batch - see docs/NEO4J_SETUP.md
      @graph_service = Graph::QueryService.new(nil)  # Query ALL Neo4j data
      @visualization_generator = VisualizationGenerator.new(ekn: ekn)
      @fine_tuned_model = get_ekn_model
      @stats = @graph_service.get_statistics
    end
    
    def navigate(user_input)
      # 1. Search for relevant entities in the graph
      entities = search_for_entities(user_input)
      
      # 2. Find paths if we have entities
      paths = find_paths_for_entities(entities) if entities.any?
      
      # 3. Build grounded context from real graph data
      context = build_grounded_context(entities, paths)
      
      # 4. Check if we should generate a visualization
      visualization = @visualization_generator.generate_for_query(
        user_input, 
        { entities: entities, paths: paths }
      )
      
      # 5. Generate response using structured outputs
      response = generate_structured_response(user_input, context, entities, paths)
      
      # Add visualization to response if generated
      response[:visualization] = visualization if visualization
      
      response
    end
    
    private
    
    def get_ekn_model
      job = FineTuneJob.find_by(ingest_batch_id: @ekn.id, status: 'succeeded')
      model = job&.fine_tuned_model || OpenaiConfig::SettingsManager.model_for('navigation')
      Rails.logger.info "Using model: #{model}"
      model
    end
    
    def search_for_entities(text)
      # Extract meaningful words
      words = text.downcase.split(/\W+/) - %w[what is the how does tell me about show]
      
      entities = []
      words.each do |word|
        [word, word.capitalize].each do |variant|
          results = @graph_service.search_entities(variant, limit: 3)
          entities.concat(results) if results.any?
        end
      end
      
      entities.uniq { |e| e[:id] }
    end
    
    def find_paths_for_entities(entities)
      return [] unless entities.size >= 2
      
      from = entities[0]
      to = entities[1]
      
      paths = @graph_service.find_paths(from[:id], to[:id], max_length: 3)
      paths.first(2) # Limit to 2 paths
    rescue => e
      Rails.logger.error "Path finding error: #{e.message}"
      []
    end
    
    def build_grounded_context(entities, paths)
      facts = []
      
      # Add graph statistics as facts
      facts << "The knowledge graph contains #{@stats[:total_nodes]} nodes"
      facts << "There are #{@stats[:total_relationships]} relationships"
      
      @stats[:nodes_by_type].each do |type, count|
        facts << "#{count} #{type} nodes exist"
      end
      
      # Add entity facts
      if entities.any?
        entities.each do |e|
          facts << "#{e[:name]} is a #{e[:type]} (ID: #{e[:id]})"
        end
      end
      
      # Add path facts
      if paths&.any?
        paths.each do |p|
          facts << "Path discovered: #{p[:path_text]}"
        end
      end
      
      {
        facts: facts,
        entity_names: entities.map { |e| e[:name] },
        path_count: paths&.size || 0
      }
    end
    
    def generate_structured_response(user_input, context, entities, paths)
      # Use the Responses API with structured outputs
      response = @client.responses.create(
        model: @fine_tuned_model,
        input: [
          {
            role: :system,
            content: "You are the Enliterator Knowledge Navigator. Generate a response based on these facts:\n" +
                     context[:facts].join("\n") +
                     "\n\nRespond naturally about what you found in the graph."
          },
          {
            role: :user,
            content: user_input
          }
        ],
        text: NavigationResponse,
        temperature: 0.5
      )
      
      # Extract the structured response
      result = response.output
        .flat_map { |output| output.content }
        .grep_v(OpenAI::Models::Responses::ResponseOutputRefusal)
        .first
      
      if result
        navigation = result.parsed # Instance of NavigationResponse
        
        {
          message: navigation.message,
          suggestions: navigation.suggestions,
          grounded_in: {
            total_nodes: @stats[:total_nodes],
            total_relationships: @stats[:total_relationships],
            entities_found: entities.size,
            paths_traced: navigation.paths_explored
          },
          entities: navigation.entities_found,
          paths: paths&.map { |p| p[:path_text] } || [],
          confidence: navigation.confidence
        }
      else
        # Fallback response
        {
          message: "I found #{entities.size} entities in the knowledge graph related to your query.",
          suggestions: ["Tell me more", "Show connections"],
          grounded_in: {
            total_nodes: @stats[:total_nodes],
            total_relationships: @stats[:total_relationships],
            entities_found: entities.size,
            paths_traced: 0
          },
          entities: entities.map { |e| "#{e[:name]} (#{e[:type]})" },
          paths: []
        }
      end
    rescue => e
      Rails.logger.error "StructuredNavigator error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      
      # Return a grounded fallback
      {
        message: "I can help you explore the #{@stats[:total_nodes]} nodes in this knowledge graph. What would you like to know?",
        suggestions: ["What concepts are available?", "Show me relationships"],
        grounded_in: @stats,
        entities: [],
        paths: []
      }
    end
  end
end