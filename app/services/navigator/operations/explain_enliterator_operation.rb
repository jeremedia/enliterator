module Navigator
  module Operations
    class ExplainEnliteratorOperation < BaseOperation
      def initialize(user_text)
        super(nil)
        @user_text = user_text.downcase
      end
      
      def execute
        {
          success: true,
          topic: determine_topic,
          explanation: generate_explanation
        }
      end
      
      private
      
      def determine_topic
        if @user_text.include?('enliteracy') || @user_text.include?('literacy')
          :enliteracy_process
        elsif @user_text.include?('stage') || @user_text.include?('pipeline')
          :pipeline_stages
        elsif @user_text.include?('how') || @user_text.include?('work')
          :how_it_works
        else
          :general_overview
        end
      end
      
      def generate_explanation
        case determine_topic
        when :enliteracy_process
          {
            main: "Enliteracy is the process of making a dataset 'literate' - able to converse naturally about its contents.",
            details: [
              "It transforms raw data into a knowledge graph with semantic understanding",
              "The process identifies entities, relationships, and context across 10 pools of meaning",
              "A literacy score (0-100) measures how well the system can answer questions about the data",
              "Score of 70+ means the dataset can reliably engage in natural conversation"
            ],
            stages: "The 9-stage pipeline takes data from raw files to a conversational Knowledge Navigator"
          }
        when :pipeline_stages
          {
            main: "Enliterator processes data through 9 stages to create Knowledge Navigators:",
            stages: [
              "Stage 0: Frame the Mission - Define goals and configure the process",
              "Stage 1: Intake - Discover, hash, and deduplicate data bundles",
              "Stage 2: Rights & Provenance - Track licenses and consent",
              "Stage 3: Lexicon Bootstrap - Extract canonical terms and meanings",
              "Stage 4: Pool Filling - Identify entities in the Ten Pool Canon",
              "Stage 5: Graph Assembly - Build Neo4j knowledge graph",
              "Stage 6: Representations - Create vector embeddings for search",
              "Stage 7: Literacy Scoring - Measure understanding and identify gaps",
              "Stage 8: Deliverables - Generate prompt packs and evaluations",
              "Stage 9: Knowledge Navigator - The conversational interface you're using now!"
            ]
          }
        when :how_it_works
          {
            main: "Enliterator works by understanding data at multiple levels:",
            process: [
              "First, it ingests your documents and extracts structured knowledge",
              "It identifies Ideas (concepts), Manifests (things), Experiences (events), and more",
              "These become nodes in a knowledge graph with meaningful relationships",
              "Vector embeddings enable semantic search and understanding",
              "Finally, a conversational interface lets you explore naturally"
            ],
            result: "You get a Knowledge Navigator - like me - that understands and can discuss your data"
          }
        else
          {
            main: "Enliterator transforms datasets into Knowledge Navigators - natural language interfaces to your data.",
            key_points: [
              "Built on Rails 8 with Neo4j graph database and OpenAI integration",
              "Processes data through 9 stages from intake to conversation",
              "Creates literate technology that can explain itself and its data",
              "You're experiencing it right now through this conversation!"
            ]
          }
        end
      end
    end
  end
end