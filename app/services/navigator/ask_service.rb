# frozen_string_literal: true

module Navigator
  # Citation model
  class CitationModel < OpenAI::Helpers::StructuredOutput::BaseModel
    required :item_id, String, doc: "ID of the cited item"
    required :snippet, String, doc: "Relevant text snippet"
  end
  
  # Response model for navigator answers
  class NavigatorAnswerResponse < OpenAI::Helpers::StructuredOutput::BaseModel
    required :answer, String, doc: "The natural language answer to the question"
    required :confidence, Float, doc: "Confidence score 0-1"
    required :citations, OpenAI::ArrayOf[CitationModel], doc: "Supporting citations"
  end
  
  class AskService < OpenaiConfig::BaseExtractionService
    attr_reader :ekn, :question
    
    def initialize(ekn:, question:)
      @ekn = ekn
      @question = question
      @navigator = Graph::NavigatorService.new(ekn: ekn)
      super()
    end
    
    protected
    
    def response_model_class
      NavigatorAnswerResponse
    end
    
    def model_for_task
      OpenaiConfig::SettingsManager.model_for(:answer)
    end
    
    def temperature_for_task
      OpenaiConfig::SettingsManager.temperature_for(:answer)
    end
    
    def content_for_extraction
      # Gather context and format for extraction
      context = gather_context
      
      <<~CONTENT
        Question: #{@question}
        
        Context from the knowledge graph:
        #{format_context(context)}
        
        Please provide a clear, concise answer based on this context.
      CONTENT
    end
    
    
    def transform_result(parsed_result)
      context = gather_context
      
      {
        question: @question,
        answer: parsed_result.answer,
        path_sentence: context[:path_sentence],
        citations: parsed_result.citations.map(&:to_h),
        rights_echo: context[:rights_echo],
        mode_hints: [:conversation]
      }
    end
    
    private
    
    def gather_context
      # Use the existing NavigatorService to find entities and paths
      entities = @navigator.send(:find_entities_in_question, @question)
      
      context = {
        entities: entities,
        paths: [],
        path_sentence: nil,
        citations: []
      }
      
      if entities.any?
        # Try to find paths between entities
        if entities.length >= 2
          path = @navigator.send(:find_path_between, entities[0][:id], entities[1][:id])
          if path
            # find_path_between returns a Neo4j path object, needs textization
            sentence = @navigator.textize_path(path)
            context[:paths] << { sentence: sentence }
            context[:path_sentence] = sentence
          end
        elsif entities.length == 1
          # Get relationships for single entity
          paths = @navigator.paths_for_entity(entities[0][:id], max_hops: 2)
          if paths && paths.any?
            context[:paths] = paths.first(3)
            # paths_for_entity returns hashes with :sentence key
            context[:path_sentence] = paths.first[:sentence] if paths.first.is_a?(Hash)
          end
        end
      end
      
      context
    end
    
    def build_messages
      context = gather_context
      
      system_prompt = <<~PROMPT
        You are the Enliterator Knowledge Navigator, an AI assistant that helps users understand the Enliterator codebase.
        
        The Enliterator is a Rails application that transforms datasets into "Enliterated Knowledge Navigators" (EKNs).
        It processes data through a 10-stage pipeline including intake, rights management, lexicon extraction, 
        knowledge graph assembly, and fine-tuning.
        
        The knowledge graph uses the Ten Pool Canon:
        - Idea: Concepts and principles
        - Practical: Methods and processes  
        - Experience: Stories and testimonials
        - Manifest: Physical/digital artifacts
        - Character: People and agents
        - Time: Temporal entities
        - Space: Locations
        - Lifecycle: States and transitions
        - Symbolic: Symbols and meanings
        - Relator: Relationships
        
        Answer questions based on the provided context from the knowledge graph.
        Be concise and specific to the Enliterator codebase.
      PROMPT
      
      user_prompt = <<~PROMPT
        Question: #{@question}
        
        Context from the knowledge graph:
        #{format_context(context)}
        
        Please provide a clear, concise answer based on this context.
        If the context doesn't fully answer the question, acknowledge what information is available
        and what might be missing.
      PROMPT
      
      [
        { role: "system", content: system_prompt },
        { role: "user", content: user_prompt }
      ]
    end
    
    def format_context(context)
      parts = []
      
      if context[:entities].any?
        parts << "Relevant entities found:"
        context[:entities].each do |entity|
          parts << "- #{entity[:pool]}(#{entity[:label]})"
        end
      end
      
      if context[:paths].any?
        parts << "\nRelationship paths:"
        context[:paths].each do |path|
          parts << "- #{path[:sentence]}" if path[:sentence]
        end
      end
      
      if context[:path_sentence]
        parts << "\nMain path: #{context[:path_sentence]}"
      end
      
      parts.join("\n")
    end
  end
end