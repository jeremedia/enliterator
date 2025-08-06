# The REAL Knowledge Navigator - powered by the fine-tuned model
# This uses the trained model to understand, navigate, and respond
module Navigator
  class ModelNavigator
    def initialize(ekn:)
      @ekn = ekn
      @client = OPENAI
      @graph_service = Graph::QueryService.new(ekn.id)
      
      # Use the EKN's OWN fine-tuned model!
      @fine_tuned_model = get_ekn_model
      
      unless @fine_tuned_model
        raise "This EKN (#{@ekn.name}) doesn't have a trained Knowledge Navigator model yet!"
      end
    end
    
    private
    
    def get_ekn_model
      # Get the fine-tuned model trained on THIS specific EKN's knowledge graph
      job = FineTuneJob.find_by(ingest_batch_id: @ekn.id, status: 'succeeded')
      job&.fine_tuned_model
    end
    
    public
    
    def navigate(user_input)
      # Step 1: Let the fine-tuned model understand the query
      understanding = understand_query(user_input)
      
      # Step 2: Execute the model's chosen operations
      graph_context = execute_navigation(understanding)
      
      # Step 3: Let the model generate response from actual graph data
      response = generate_from_knowledge(user_input, understanding, graph_context)
      
      {
        message: response[:content],
        paths_explored: response[:paths],
        confidence: understanding[:confidence],
        sources: graph_context[:sources]
      }
    end
    
    private
    
    def understand_query(user_input)
      # Use the fine-tuned model to understand intent and plan navigation
      messages = [
        {
          role: "system",
          content: "You are a Knowledge Navigator for the Enliterator Meta-EKN. " +
                   "Analyze the user's query and determine: " +
                   "1) The canonical form of their question " +
                   "2) Which graph operations to perform (search, traverse, aggregate) " +
                   "3) Which pools to focus on (Idea, Manifest, Experience, etc.) " +
                   "4) Key entities to explore. " +
                   "Respond in JSON format."
        },
        {
          role: "user",
          content: user_input
        }
      ]
      
      response = @client.chat.completions.create(
        model: @fine_tuned_model,
        messages: messages,
        temperature: 0.3,
        response_format: { type: "json_object" }
      )
      
      JSON.parse(response.choices.first.message.content).symbolize_keys
    rescue => e
      Rails.logger.error "Model understanding failed: #{e.message}"
      { 
        canonical_query: user_input,
        operations: [:search],
        pools: [:all],
        entities: [],
        confidence: 0.5
      }
    end
    
    def execute_navigation(understanding)
      context = {
        nodes: [],
        paths: [],
        statistics: {},
        sources: []
      }
      
      # Get graph statistics if needed
      if understanding[:operations]&.include?('aggregate') || understanding[:operations]&.include?('statistics')
        context[:statistics] = @graph_service.get_statistics
      end
      
      # Search for keywords and entities
      keywords = understanding[:keywords] || understanding[:entities] || []
      keywords << understanding[:canonical_query] if understanding[:canonical_query]
      
      keywords.uniq.each do |keyword|
        next if keyword.blank?
        results = @graph_service.search_entities(keyword.to_s, limit: 5)
        context[:nodes].concat(results) if results.any?
        context[:sources] << "Graph search: #{keyword}" if results.any?
      end
      
      # Perform semantic search if we have a query
      if understanding[:canonical_query]
        semantic_results = perform_semantic_search(understanding[:canonical_query])
        context[:nodes].concat(semantic_results)
        context[:sources] << "Semantic search"
      end
      
      # Traverse paths between nodes if we found multiple
      if context[:nodes].size >= 2
        paths = find_paths_between_nodes(context[:nodes].first(2))
        context[:paths] = paths
        context[:sources] << "Path traversal"
      end
      
      context
    end
    
    def generate_from_knowledge(user_input, understanding, graph_context)
      # Build context from actual graph data
      graph_description = build_graph_description(graph_context)
      
      messages = [
        {
          role: "system",
          content: "You are the Enliterator Knowledge Navigator. " +
                   "Generate a response based on the actual knowledge graph data provided. " +
                   "Use the paths, nodes, and relationships to construct your answer. " +
                   "Be specific and reference actual entities from the graph."
        },
        {
          role: "user",
          content: "User asked: #{user_input}\n\n" +
                   "Graph context:\n#{graph_description}\n\n" +
                   "Generate a natural response that navigates through this knowledge."
        }
      ]
      
      response = @client.chat.completions.create(
        model: @fine_tuned_model,
        messages: messages,
        temperature: 0.7
      )
      
      {
        content: response.choices.first.message.content,
        paths: graph_context[:paths],
        model: @fine_tuned_model
      }
    end
    
    def build_graph_description(context)
      description = []
      
      if context[:statistics].any?
        stats = context[:statistics]
        description << "The graph contains #{stats[:total_nodes]} nodes with #{stats[:total_relationships]} relationships."
        if stats[:nodes_by_type]
          description << "Node types: #{stats[:nodes_by_type].map { |k,v| "#{v} #{k}" }.join(', ')}"
        end
      end
      
      if context[:nodes].any?
        description << "\nRelevant entities found:"
        context[:nodes].first(10).each do |node|
          description << "- #{node[:name]} (#{node[:type]}): #{node[:description] || 'No description'}"
        end
      end
      
      if context[:paths].any?
        description << "\nRelationship paths discovered:"
        context[:paths].each do |path|
          description << "- #{path[:description]}"
        end
      end
      
      description.join("\n")
    end
    
    def perform_semantic_search(query)
      # Use Neo4j GenAI embeddings for semantic search
      embedding_service = ::Neo4j::EmbeddingService.new(@ekn.id)
      results = embedding_service.semantic_search(query, limit: 5)
      
      results.map do |result|
        {
          id: result['entity_id'],
          name: result['content'].split.first(5).join(' '),
          type: result['entity_type'],
          similarity: result['similarity'],
          description: result['content']
        }
      end
    rescue => e
      Rails.logger.error "Semantic search failed: #{e.message}"
      []
    end
    
    def find_paths_between_nodes(nodes)
      return [] unless nodes.size >= 2
      
      from_id = nodes[0][:id]
      to_id = nodes[1][:id]
      
      paths = @graph_service.find_paths(from_id, to_id, max_length: 3)
      
      paths.map do |path|
        {
          description: path[:path_text],
          nodes: path[:nodes],
          relationships: path[:relationships]
        }
      end
    rescue => e
      Rails.logger.error "Path finding failed: #{e.message}"
      []
    end
  end
end