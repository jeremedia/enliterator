# Simplified GROUNDED Navigator - every response includes real graph data
module Navigator
  class GroundedNavigator
    def initialize(ekn:)
      @ekn = ekn
      @client = OPENAI
      @graph_service = Graph::QueryService.new(ekn.id)
      @fine_tuned_model = get_ekn_model
      
      # Cache basic stats to avoid repeated queries
      @stats = @graph_service.get_statistics
    end
    
    def navigate(user_input)
      # 1. Search for relevant entities
      entities = search_for_entities(user_input)
      
      # 2. Find paths if we have entities
      paths = find_paths_for_entities(entities) if entities.any?
      
      # 3. Generate grounded response
      generate_grounded_response(user_input, entities, paths)
    end
    
    private
    
    def get_ekn_model
      job = FineTuneJob.find_by(ingest_batch_id: @ekn.id, status: 'succeeded')
      job&.fine_tuned_model || ENV.fetch('OPENAI_MODEL', 'gpt-4.1-2025-04-14') # Fallback to configured model
    end
    
    def search_for_entities(text)
      # Extract keywords - let the fine-tuned model understand domain concepts
      words = text.downcase.split(/\W+/) - %w[what is the how does tell me about show]
      
      entities = []
      words.each do |word|
        # Search with variations
        [word, word.capitalize].each do |variant|
          results = @graph_service.search_entities(variant, limit: 3)
          entities.concat(results) if results.any?
        end
      end
      
      entities.uniq { |e| e[:id] }
    end
    
    def find_paths_for_entities(entities)
      return [] unless entities.size >= 2
      
      # Just find one path between first two entities
      from = entities[0]
      to = entities[1]
      
      paths = @graph_service.find_paths(from[:id], to[:id], max_length: 3)
      paths.first(2) # Limit to 2 paths
    rescue => e
      Rails.logger.error "Path finding error: #{e.message}"
      []
    end
    
    def generate_grounded_response(user_input, entities, paths)
      # Build the grounded context
      context = build_grounded_context(entities, paths)
      
      messages = [
        {
          role: "system",
          content: "You are the Enliterator Knowledge Navigator. " +
                   "Generate a response using ONLY this actual graph data:\n\n" +
                   context +
                   "\n\nInclude specific numbers and entity names from above."
        },
        {
          role: "user",
          content: user_input
        }
      ]
      
      response = @client.chat.completions.create(
        model: @fine_tuned_model,
        messages: messages,
        temperature: 0.5
      )
      
      {
        message: response.choices.first.message.content,
        grounded_in: {
          total_nodes: @stats[:total_nodes],
          total_relationships: @stats[:total_relationships],
          entities_found: entities.size,
          paths_traced: paths&.size || 0
        },
        entities: entities.map { |e| "#{e[:name]} (#{e[:type]})" },
        paths: paths&.map { |p| p[:path_text] } || []
      }
    end
    
    def build_grounded_context(entities, paths)
      context = []
      
      # Graph statistics
      context << "GRAPH CONTAINS:"
      context << "- #{@stats[:total_nodes]} total nodes"
      context << "- #{@stats[:total_relationships]} total relationships"
      @stats[:nodes_by_type].each do |type, count|
        context << "- #{count} #{type} nodes"
      end
      
      # Found entities
      if entities.any?
        context << "\nFOUND ENTITIES:"
        entities.each do |e|
          context << "- #{e[:name]} (#{e[:type]}, ID: #{e[:id]})"
        end
      else
        context << "\nNO SPECIFIC ENTITIES FOUND FOR THIS QUERY"
      end
      
      # Paths
      if paths&.any?
        context << "\nPATHS DISCOVERED:"
        paths.each do |p|
          context << "- #{p[:path_text]}"
        end
      end
      
      context.join("\n")
    end
  end
end