# frozen_string_literal: true

# Orchestrates query processing through routing, tool execution, and enrichment
class QueryOrchestrator
  attr_reader :ekn, :conversation, :router, :tools
  
  def initialize(ekn:, conversation: nil)
    @ekn = ekn
    @conversation = conversation
    @router = nil # Will be created per query
    @tools = initialize_tools
  end
  
  def process(query)
    Rails.logger.info "QueryOrchestrator processing: #{query}"
    
    # Step 1: Route query through fine-tuned model
    routing_result = route_query(query)
    
    return routing_result if routing_result[:error]
    
    # Step 2: Execute primary tool
    tool_result = execute_tool(routing_result)
    
    # Step 3: Enrich with additional context
    enriched_result = enrich_results(tool_result, routing_result)
    
    # Step 4: Format for response generation
    format_for_response(enriched_result, routing_result)
  rescue => e
    Rails.logger.error "QueryOrchestrator error: #{e.message}"
    Rails.logger.error e.backtrace.first(10).join("\n")
    
    {
      error: e.message,
      query: query,
      fallback_response: "I encountered an error processing your query. Please try rephrasing or ask a different question."
    }
  end
  
  alias call process
  
  private
  
  def initialize_tools
    {
      'search' => Mcp::Tools::SimpleSearchTool.new(ekn: @ekn),
      'fetch' => Mcp::Tools::FetchTool.new(ekn: @ekn),
      'bridge' => Mcp::Tools::BridgeTool.new(ekn: @ekn),
      'extract_and_link' => Mcp::Tools::ExtractAndLinkTool.new(ekn: @ekn)
    }
  rescue => e
    # If some tools don't exist yet, just use what we have
    Rails.logger.info "Some tools not available yet: #{e.message}"
    {
      'search' => Mcp::Tools::SimpleSearchTool.new(ekn: @ekn)
    }
  end
  
  def route_query(query)
    # Get context from previous messages if available
    context = build_context_from_conversation
    
    # Route through fine-tuned model
    @router = Routing::FineTuneRouter.new(
      query: query,
      ekn: @ekn,
      context: context
    )
    
    result = @router.call
    
    if result[:success] == false
      # Fallback to simple search if routing fails
      Rails.logger.warn "Routing failed, using fallback"
      return {
        query: query,
        normalized_query: query,
        primary_tool: 'search',
        tool_params: { query: query, top_k: 10 },
        confidence: 0.5,
        reasoning: "Routing failed, using keyword search as fallback",
        error: result[:error]
      }
    end
    
    result
  end
  
  def execute_tool(routing_result)
    tool_name = routing_result[:primary_tool]
    tool_params = routing_result[:tool_params]
    
    tool = @tools[tool_name]
    
    unless tool
      Rails.logger.warn "Tool '#{tool_name}' not found, using search"
      tool = @tools['search']
      tool_name = 'search'
      tool_params = { query: routing_result[:query], top_k: 10 }
    end
    
    # Filter params based on what the tool accepts
    filtered_params = filter_params_for_tool(tool_name, tool_params)
    
    # Check if params were modified (fallback to search)
    if filtered_params != filter_params_for_tool(tool_name, tool_params)
      tool = @tools['search']
      tool_name = 'search'
    end
    
    Rails.logger.info "Executing tool: #{tool_name} with params: #{filtered_params.inspect}"
    
    # Execute the tool
    result = tool.execute(**filtered_params.symbolize_keys)
    
    # Add routing info to result
    result[:routing] = {
      tool: tool_name,
      confidence: routing_result[:confidence],
      reasoning: routing_result[:reasoning]
    }
    
    result
  rescue => e
    Rails.logger.error "Tool execution failed: #{e.message}, falling back to search"
    
    # Fallback to search if tool execution fails
    fallback_result = @tools['search'].execute(query: @query, top_k: 10)
    fallback_result[:routing] = {
      tool: 'search',
      confidence: 0.5,
      reasoning: "Fallback to search after #{tool_name} failed: #{e.message}"
    }
    fallback_result
  end
  
  def filter_params_for_tool(tool_name, params)
    case tool_name
    when 'search'
      # SimpleSearchTool accepts: query, top_k, pools, require_rights
      filtered = params.slice(:query, :top_k, :pools, :require_rights)
      
      # Ensure query parameter is always present
      filtered[:query] ||= @query if @query
      filtered[:top_k] ||= 10
      
      filtered
    when 'fetch'
      # FetchTool would accept: id, include_relations, relation_depth, pools, as_of
      filtered = params.slice(:id, :include_relations, :relation_depth, :pools, :as_of)
      
      # If no valid id, fallback to search
      if filtered[:id].blank?
        Rails.logger.warn "Fetch tool selected but no ID provided, falling back to search"
        return filter_params_for_tool('search', { query: @query, top_k: 10 })
      end
      
      filtered
    when 'bridge'
      # BridgeTool would accept: a, b, top_k
      params.slice(:a, :b, :top_k)
    when 'extract_and_link'
      # ExtractAndLinkTool would accept: text, mode, link_threshold
      params.slice(:text, :mode, :link_threshold)
    else
      params
    end
  end
  
  def enrich_results(tool_result, routing_result)
    # Skip enrichment if fetch tool not available
    return tool_result unless @tools['fetch']
    
    # If we have canonical entities from routing, try to fetch additional info
    if routing_result[:canonical_entities]&.any?
      # Try to find and fetch the first canonical entity
      # (In production, would match entity names to IDs more carefully)
      enrichments = []
      
      routing_result[:canonical_entities].first(2).each do |entity_name|
        # Search for the entity by name
        search_result = @tools['search'].execute(query: entity_name, top_k: 1)
        if search_result[:items]&.first
          entity_id = search_result[:items].first[:entity_id]
          begin
            fetch_result = @tools['fetch'].execute(id: entity_id)
            enrichments << fetch_result if fetch_result
          rescue => e
            Rails.logger.warn "Could not fetch entity #{entity_id}: #{e.message}"
          end
        end
      end
      
      tool_result[:enrichments] = enrichments if enrichments.any?
    end
    
    tool_result
  end
  
  def format_for_response(result, routing_result)
    # Extract key information for the AI to use
    items = result[:items] || []
    
    # Build path sentences from results
    path_sentences = items.map { |item| item[:path_preview] }.compact.uniq
    
    # Build citations
    citations = items.map do |item|
      {
        entity_id: item[:entity_id],
        entity_name: item[:entity_name],
        entity_type: item[:entity_type],
        relevance: item[:similarity] || item[:relevance]
      }
    end
    
    # Format the final response
    {
      original_query: routing_result[:query],
      normalized_query: routing_result[:normalized_query],
      canonical_entities: routing_result[:canonical_entities] || [],
      detected_pools: routing_result[:detected_pools] || [],
      tool_used: routing_result[:primary_tool],
      confidence: routing_result[:confidence],
      reasoning: routing_result[:reasoning],
      results: {
        items: items,
        total: items.size,
        meta: result[:meta]
      },
      path_sentences: path_sentences,
      citations: citations,
      enrichments: result[:enrichments],
      context_for_llm: build_llm_context(result, routing_result)
    }
  end
  
  def build_context_from_conversation
    return {} unless @conversation
    
    # Get recent entities mentioned
    recent_messages = @conversation.messages.recent(5)
    previous_entities = []
    
    recent_messages.each do |msg|
      # Extract entity mentions from metadata if available
      if msg.metadata['canonical_entities']
        previous_entities.concat(msg.metadata['canonical_entities'])
      end
    end
    
    {
      previous_entities: previous_entities.uniq
    }
  end
  
  def build_llm_context(result, routing_result)
    # Build a structured context for the LLM to use
    context_parts = []
    
    # Add normalized understanding
    context_parts << "Query understood as: #{routing_result[:normalized_query]}"
    
    # Add entity context
    if routing_result[:canonical_entities]&.any?
      context_parts << "Key entities: #{routing_result[:canonical_entities].join(', ')}"
    end
    
    # Add search results summary
    if result[:items]&.any?
      context_parts << "Found #{result[:items].size} relevant items:"
      result[:items].first(5).each do |item|
        context_parts << "- #{item[:entity_type]}(#{item[:entity_name]})"
        context_parts << "  #{item[:content]}" if item[:content]
        context_parts << "  Path: #{item[:path_preview]}" if item[:path_preview]
      end
    else
      context_parts << "No direct matches found in the knowledge graph."
    end
    
    # Add enrichment summary
    if result[:enrichments]&.any?
      context_parts << "\nAdditional context:"
      result[:enrichments].each do |enrichment|
        if enrichment[:properties]
          context_parts << "- #{enrichment[:label]}: #{enrichment[:repr_text]}"
        end
      end
    end
    
    context_parts.join("\n")
  end
end