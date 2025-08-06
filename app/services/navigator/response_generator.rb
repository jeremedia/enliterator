# Generates natural language responses from operation results
module Navigator
  class ResponseGenerator
    def generate(intent, results, user_text)
      # Transform technical results into natural conversation
      
      case intent[:type]
      when :greeting
        generate_greeting_response
      when :show_statistics
        generate_statistics_response(results)
      when :search_entities
        generate_search_response(results)
      when :explain_enliterator, :explain_process
        generate_enliterator_response(results)
      else
        generate_default_response(user_text, results)
      end
    end
    
    def generate_suggestions(intent, results)
      # Suggest natural follow-up questions based on context
      
      suggestions = []
      
      case intent[:type]
      when :show_statistics
        suggestions = [
          "Show me the Ideas in the graph",
          "What are the main Manifest nodes?",
          "Search for controllers"
        ]
      when :search_entities
        if results.values.first[:results]&.any?
          suggestions = [
            "Tell me more about the first result",
            "Show connections between these entities",
            "Find similar items"
          ]
        else
          suggestions = [
            "Try a different search term",
            "Show me all available entities",
            "What data is in this EKN?"
          ]
        end
      else
        suggestions = default_suggestions
      end
      
      suggestions
    end
    
    private
    
    def generate_greeting_response
      "Hello! I'm your Knowledge Navigator for the Enliterator Meta-EKN. I can help you explore the codebase, understand relationships, and discover insights. What would you like to know?"
    end
    
    def generate_statistics_response(results)
      stats_result = results.values.first
      return "I couldn't retrieve the statistics right now." if stats_result[:error]
      
      stats = stats_result[:data]
      total = stats[:total_nodes] || 0
      types = stats[:nodes_by_type] || {}
      
      response = "The knowledge graph contains #{total} nodes"
      
      if types.any?
        type_descriptions = types.map { |type, count| "#{count} #{type}" }.join(", ")
        response += " organized as: #{type_descriptions}"
      end
      
      response += ". The graph has #{stats[:total_relationships]} relationships connecting these entities."
      response
    end
    
    def generate_search_response(results)
      search_result = results.values.first
      return "I couldn't perform the search. Please try again." if search_result[:error]
      
      query = search_result[:query]
      found = search_result[:results] || []
      count = search_result[:count] || 0
      
      if count == 0
        "I didn't find any results for '#{query}'. Try different search terms or browse the available data."
      elsif count == 1
        item = found.first
        "I found one result: #{item[:name]} (#{item[:type]}). #{item[:description]}"
      else
        names = found.first(5).map { |r| r[:name] }.join(", ")
        "I found #{count} results for '#{query}'. Here are some: #{names}"
      end
    end
    
    def generate_enliterator_response(results)
      explain_result = results["ExplainEnliteratorOperation"] || results.values.first
      return generate_default_response("enliteracy", results) unless explain_result[:success]
      
      explain_result[:explanation]
    end
    
    def generate_default_response(user_text, results)
      "I understood you want to know about '#{user_text}', but I'm still learning how to help with that specific request. Try asking about the graph statistics, searching for entities, or asking what I can do."
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
end