# Chat Response Job with QueryOrchestrator Integration
#
# This job provides fully grounded responses by:
# 1. Using QueryOrchestrator to route queries through fine-tuned Arctic model
# 2. Executing appropriate MCP tools (search, fetch, bridge, extract_and_link)
# 3. Generating responses based ONLY on knowledge graph data
# 4. Including citations and rights echo in all responses
#
class ChatResponseGroundedJob < ApplicationJob
  queue_as :default
  
  def perform(conversation_id:, message_id:)
    @conversation_id = conversation_id
    @message_id = message_id
    conversation = Conversation.find(conversation_id)
    user_message = conversation.messages.find(message_id)
    assistant_message = nil
    
    begin
      # Create assistant message placeholder
      assistant_message = conversation.messages.create!(
        role: 'assistant',
        content: '🧠 Processing through Arctic Navigator...',
        metadata: {
          streaming: false,
          model_used: 'QueryOrchestrator + ' + conversation.ai_model,
          started_at: Time.current,
          process_trace: ['🧠 Initializing Arctic Navigator intelligence...']
        }
      )
      
      # Broadcast initial message
      broadcast_message(conversation, assistant_message)
      
      # Step 1: Process query through QueryOrchestrator
      update_trace(conversation, assistant_message, "🎯 Routing query through fine-tuned Arctic model...")
      
      orchestrator = QueryOrchestrator.new(ekn: conversation.ekn, conversation: conversation)
      orchestrator_result = orchestrator.process(user_message.content)
      
      if orchestrator_result[:error]
        raise StandardError, "QueryOrchestrator failed: #{orchestrator_result[:error]}"
      end
      
      update_trace(conversation, assistant_message, "✅ Query understood as: #{orchestrator_result[:normalized_query]}")
      update_trace(conversation, assistant_message, "🔧 Used tool: #{orchestrator_result[:tool_used]} (confidence: #{orchestrator_result[:confidence]})")
      
      # Step 2: Build grounded context for LLM
      update_trace(conversation, assistant_message, "📚 Building grounded context from knowledge graph...")
      
      grounded_context = build_grounded_context(orchestrator_result)
      
      # Step 3: Generate response using Arctic specialist model + grounded context
      update_trace(conversation, assistant_message, "🤖 Generating response with Arctic specialist knowledge...")
      
      messages = build_grounded_messages(conversation, grounded_context, orchestrator_result)
      
      # Use Arctic fine-tuned model for domain expertise
      arctic_model = OpenaiConfig::SettingsManager.model_for(:routing) # Arctic specialist model
      
      response = OPENAI.chat.completions.create(
        model: arctic_model,
        messages: messages,
        temperature: 0.3, # Lower temperature for factual responses
        max_tokens: 1500
      )
      
      # Step 4: Extract and finalize response
      final_content = response.choices.first.message.content
      
      # Add citations and rights echo
      final_response = format_grounded_response(final_content, orchestrator_result)
      
      # Update assistant message with final content
      assistant_message.update!(
        content: final_response,
        metadata: assistant_message.metadata.merge(
          model_used: arctic_model,
          usage: response.usage&.to_h,
          grounded_data: {
            original_query: orchestrator_result[:original_query],
            normalized_query: orchestrator_result[:normalized_query],
            tool_used: orchestrator_result[:tool_used],
            confidence: orchestrator_result[:confidence],
            canonical_entities: orchestrator_result[:canonical_entities],
            citations: orchestrator_result[:citations],
            results_count: orchestrator_result.dig(:results, :total)
          },
          completed_at: Time.current,
          is_grounded: true # Mark as grounded response
        )
      )
      
      # Broadcast final message
      broadcast_message(conversation, assistant_message)
      update_trace(conversation, assistant_message, "✨ Grounded response ready with #{orchestrator_result[:citations]&.size || 0} citations")
      
    rescue => e
      Rails.logger.error "ChatResponseGroundedJob failed: #{e.class} - #{e.message}"
      Rails.logger.error e.backtrace.first(10).join("\n")
      
      handle_error(conversation, assistant_message, e)
    ensure
      # Always hide typing indicator
      broadcast_typing_indicator(conversation, typing: false) rescue nil
    end
  end
  
  private
  
  def build_grounded_context(orchestrator_result)
    context_parts = []
    
    # Query understanding
    context_parts << "**Query Analysis:**"
    context_parts << "- Original: #{orchestrator_result[:original_query]}"
    context_parts << "- Normalized: #{orchestrator_result[:normalized_query]}"
    context_parts << "- Tool used: #{orchestrator_result[:tool_used]} (#{orchestrator_result[:confidence]} confidence)"
    context_parts << "- Reasoning: #{orchestrator_result[:reasoning]}"
    
    # Canonical entities
    if orchestrator_result[:canonical_entities]&.any?
      context_parts << "\n**Key Entities Identified:**"
      orchestrator_result[:canonical_entities].each do |entity|
        context_parts << "- #{entity}"
      end
    end
    
    # Pool analysis
    if orchestrator_result[:detected_pools]&.any?
      context_parts << "\n**Relevant Knowledge Pools:**"
      orchestrator_result[:detected_pools].each do |pool|
        context_parts << "- #{pool}"
      end
    end
    
    # Search results
    if orchestrator_result.dig(:results, :items)&.any?
      context_parts << "\n**Knowledge Graph Results (#{orchestrator_result.dig(:results, :total)} found):**"
      
      orchestrator_result[:results][:items].first(10).each_with_index do |item, i|
        context_parts << "\n#{i + 1}. **#{item[:entity_type]}**: #{item[:entity_name]}"
        context_parts << "   ID: #{item[:entity_id]}"
        context_parts << "   Content: #{item[:content]}" if item[:content]
        context_parts << "   Relevance: #{item[:similarity] || item[:relevance]}" if item[:similarity] || item[:relevance]
        context_parts << "   Path: #{item[:path_preview]}" if item[:path_preview]
      end
    else
      context_parts << "\n**No direct matches found in knowledge graph.**"
    end
    
    # Path sentences
    if orchestrator_result[:path_sentences]&.any?
      context_parts << "\n**Relationship Paths:**"
      orchestrator_result[:path_sentences].each do |path|
        context_parts << "- #{path}"
      end
    end
    
    # Enrichments
    if orchestrator_result[:enrichments]&.any?
      context_parts << "\n**Additional Context:**"
      orchestrator_result[:enrichments].each do |enrichment|
        context_parts << "- #{enrichment[:label]}: #{enrichment[:repr_text]}" if enrichment[:label]
      end
    end
    
    context_parts.join("\n")
  end
  
  def build_grounded_messages(conversation, grounded_context, orchestrator_result)
    messages = []
    
    # System prompt emphasizing grounded responses
    system_prompt = build_grounded_system_prompt(conversation.ekn, orchestrator_result)
    messages << { role: "system", content: system_prompt }
    
    # Add recent conversation history for context
    conversation.messages.where(role: ['user', 'assistant'])
                        .order(:created_at)
                        .last(10)
                        .each do |msg|
      messages << { role: msg.role, content: msg.content }
    end
    
    # Add the grounded context as a special system message
    messages << { 
      role: "system", 
      content: "**GROUNDED KNOWLEDGE CONTEXT:**\n\n#{grounded_context}\n\n**RESPONSE INSTRUCTIONS:** Base your response ONLY on the above knowledge graph data. Include specific entity IDs and cite your sources." 
    }
    
    messages
  end
  
  def build_grounded_system_prompt(ekn, orchestrator_result)
    <<~PROMPT
      You are the **#{ekn.name}**, an Enliterated Knowledge Navigator with deep expertise in Arctic research.
      
      You are powered by a fine-tuned Arctic specialist model and have access to a knowledge graph with #{ekn.total_nodes} entities and #{ekn.total_relationships} relationships.
      
      **CRITICAL GROUNDING RULES:**
      1. **Base responses ONLY on the provided knowledge graph data**
      2. **Never invent or assume information not in the context**
      3. **Always cite specific entity IDs when referencing knowledge**
      4. **Include path sentences when showing relationships**
      5. **Respect rights and only quote content marked as publishable**
      6. **If knowledge graph has no relevant data, explicitly state this**
      
      **Your Expertise:** Arctic research including environmental conditions, expeditions, scientific studies, personnel challenges, infrastructure, and polar ecosystems.
      
      **Query Understanding:**
      - Tool used: #{orchestrator_result[:tool_used]}
      - Confidence: #{orchestrator_result[:confidence]}
      - Reasoning: #{orchestrator_result[:reasoning]}
      
      **Response Format:**
      - Provide substantive answers based on the knowledge graph
      - Include specific citations: [Entity: entity_name (ID: entity_id)]
      - Show relationship paths when relevant
      - End with a rights echo showing data source compliance
      
      Remember: You are a domain specialist, not a generic AI. Your responses should demonstrate deep Arctic research knowledge while being completely grounded in the provided data.
    PROMPT
  end
  
  def format_grounded_response(content, orchestrator_result)
    response_parts = [content]
    
    # Add citations section
    if orchestrator_result[:citations]&.any?
      response_parts << "\n\n---\n\n**Citations:**"
      orchestrator_result[:citations].each_with_index do |citation, i|
        response_parts << "#{i + 1}. #{citation[:entity_type]}: #{citation[:entity_name]} (ID: #{citation[:entity_id]})"
      end
    end
    
    # Add path sentences if available
    if orchestrator_result[:path_sentences]&.any?
      response_parts << "\n**Relationship Paths:**"
      orchestrator_result[:path_sentences].each do |path|
        response_parts << "- #{path}"
      end
    end
    
    # Rights echo
    response_parts << "\n\n---\n\n*Response grounded in Arctic Research Navigator knowledge graph. #{orchestrator_result.dig(:results, :total) || 0} entities consulted. Rights-compliant content only.*"
    
    response_parts.join("\n")
  end
  
  def broadcast_message(conversation, message)
    Turbo::StreamsChannel.broadcast_append_to(
      "conversation_#{conversation.id}",
      target: "messages",
      partial: "ekns/chat/message",
      locals: { message: message, ekn: conversation.ekn }
    )
  end
  
  def update_trace(conversation, assistant_message, trace_message)
    # Add to trace history
    traces = assistant_message.metadata['process_trace'] || []
    traces << trace_message
    
    # Update the message metadata
    assistant_message.update!(
      metadata: assistant_message.metadata.merge('process_trace' => traces)
    )
    
    Rails.logger.info "Grounded Process: #{trace_message}"
  end
  
  def broadcast_typing_indicator(conversation, typing:)
    if typing
      Turbo::StreamsChannel.broadcast_append_to(
        "conversation_#{conversation.id}",
        target: "messages",
        partial: "ekns/chat/typing_indicator"
      )
    else
      Turbo::StreamsChannel.broadcast_remove_to(
        "conversation_#{conversation.id}",
        target: "typing_indicator"
      )
    end
  end
  
  def handle_error(conversation, assistant_message, error)
    Rails.logger.error "ChatResponseGroundedJob Error: #{error.class} - #{error.message}"
    
    error_message = "❌ **Arctic Navigator Error**\n\n"
    error_message += "I encountered an issue processing your query through the knowledge graph.\n\n"
    error_message += "**Error**: #{error.message}\n\n"
    error_message += "Please try rephrasing your question or ask about a different Arctic research topic."
    
    if assistant_message
      assistant_message.update!(
        content: error_message,
        metadata: assistant_message.metadata.merge(
          error: error.message,
          error_class: error.class.name,
          completed_at: Time.current,
          is_error: true
        )
      )
      
      broadcast_message(conversation, assistant_message)
    end
  end
end