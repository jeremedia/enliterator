# frozen_string_literal: true

module Evaluation
  class LiterateWrapper
    EXPLANATIONS = {
      'Enliteration' => "Enliteration is the process that makes a dataset literate by modeling it into pools of meaning with explicit flows between them. It's the core concept of the Enliterator system, which transforms data collections into knowledge graphs that can answer 'why,' 'how,' and 'what's next' - not just 'what.'",
      'Ten Pool Canon' => "The Ten Pool Canon consists of Ideas, Manifests, Experiences, Relational, Evolutionary, Practical, Emanation, and optional pools (Spatial, Actor, Evidence, Risk, Method). Each pool represents a different type of meaning in your knowledge graph.",
      'Knowledge Graph' => "A knowledge graph in Enliterator connects entities across pools using a closed set of relationship verbs. This creates explicit paths that can be textized into natural language narratives.",
      'MCP' => "Model Context Protocol (MCP) provides tools for extraction, search, bridging, fetching, and spatial operations on the enliterated dataset.",
      'Literacy' => "In Enliterator, literacy means software that can converse naturally, show reasoning paths with sources, adapt to intent, and produce deliverables - treating data as a partner in meaning.",
      'Pipeline' => "The 8-stage enliteration pipeline: Intake → Rights → Lexicon → Pools → Graph → Embeddings → Literacy Scoring → Deliverables. Each stage has acceptance gates ensuring quality."
    }.freeze
    
    def self.wrap_response(raw_response, user_query)
      # Try to parse as JSON (routing response)
      begin
        routing = JSON.parse(raw_response)
        return generate_literate_response(routing, user_query)
      rescue JSON::ParserError
        # If not JSON, return as-is (already literate)
        return raw_response
      end
    end
    
    private
    
    def self.generate_literate_response(routing, user_query)
      canonical = routing['canonical']
      mcp_tool = routing['mcp']
      params = routing['params']
      
      # Build a literate response
      response = []
      
      # Add explanation if we have one
      if canonical && EXPLANATIONS[canonical]
        response << EXPLANATIONS[canonical]
      elsif routing['description']
        response << routing['description']
      else
        response << "I understand you're asking about '#{canonical || user_query}'."
      end
      
      # Add context about what we can do
      case mcp_tool
      when 'fetch'
        response << "\nI can fetch detailed information about #{canonical} from the knowledge graph, including its relationships and timeline."
      when 'search'
        response << "\nI can search for related concepts and show you how #{canonical} connects to other ideas in the system."
      when 'bridge'
        response << "\nI can find connections between #{canonical} and other concepts, showing the path through the knowledge graph."
      when 'lexicon'
        response << "\nI can show you the canonical forms and surface variations of '#{canonical}' in our lexicon."
      when 'extract_and_link'
        response << "\nI can extract and link entities related to #{canonical} from text."
      end
      
      # Add helpful next steps
      response << "\nWould you like me to:"
      response << "• Explain more about #{canonical}"
      response << "• Show related concepts"
      response << "• Walk through how it fits in the pipeline"
      
      response.join("\n")
    end
  end
end