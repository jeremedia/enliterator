# Literate Architecture for Enliterator

## Vision
Transform Enliterator from a scripted pipeline into a truly literate system that understands, explains, and converses naturally about data throughout the entire application.

## Core Principle
**Every interaction should be a conversation, not a command.**

## Architecture Components

### 1. Prompt Management System (Active Record)

```ruby
# app/models/prompt.rb
class Prompt < ApplicationRecord
  # Store ALL prompts in database for easy iteration
  # No hardcoded prompts anywhere in the app
  
  has_many :prompt_versions
  has_many :prompt_performances
  belongs_to :current_version, class_name: 'PromptVersion'
  
  # Categories
  enum category: {
    system: 0,        # Core system prompts
    interview: 1,     # Data collection prompts
    pipeline: 2,      # Pipeline operation prompts
    analysis: 3,      # Analysis and insights
    explanation: 4,   # Explaining concepts
    error: 5,        # Error handling
    coaching: 6       # User guidance
  }
  
  # Usage
  enum context: {
    global: 0,        # Used everywhere
    intake: 1,        # Stage 1 specific
    rights: 2,        # Stage 2 specific
    lexicon: 3,       # Stage 3 specific
    pools: 4,         # Stage 4 specific
    graph: 5,         # Stage 5 specific
    embeddings: 6,    # Stage 6 specific
    literacy: 7,      # Stage 7 specific
    deliverables: 8   # Stage 8 specific
  }
end

# app/models/prompt_version.rb
class PromptVersion < ApplicationRecord
  belongs_to :prompt
  has_many :performances
  
  # A/B testing support
  enum status: {
    draft: 0,
    testing: 1,
    active: 2,
    retired: 3
  }
  
  # Template with variables
  # "I found {{entity_count}} entities in your {{dataset_type}} data."
  def render(variables = {})
    content.gsub(/\{\{(\w+)\}\}/) { variables[$1.to_sym] }
  end
end

# app/models/prompt_performance.rb
class PromptPerformance < ApplicationRecord
  belongs_to :prompt_version
  belongs_to :conversation
  
  # Track how well prompts perform
  # - user_satisfaction (1-5)
  # - task_completion (boolean)
  # - response_time
  # - follow_up_needed (boolean)
end
```

### 2. Literate Conversation Engine

```ruby
# app/services/literate/engine.rb
module Literate
  class Engine
    def initialize(conversation = nil)
      @conversation = conversation || Conversation.create
      @context = ContextBuilder.new(@conversation)
      @interpreter = IntentInterpreter.new
      @executor = ActionExecutor.new
    end
    
    def process(user_input)
      # 1. Add to conversation history
      @conversation.messages.create(role: 'user', content: user_input)
      
      # 2. Build context (include graph, recent ops, user prefs)
      context = @context.build
      
      # 3. Interpret intent using OpenAI
      intent = @interpreter.interpret(user_input, context)
      
      # 4. Execute actions if needed
      results = @executor.execute(intent) if intent.executable?
      
      # 5. Generate literate response
      response = generate_response(intent, results, context)
      
      # 6. Store response
      @conversation.messages.create(role: 'assistant', content: response)
      
      response
    end
    
    private
    
    def generate_response(intent, results, context)
      # Use appropriate prompt based on intent
      prompt = Prompt.find_by(
        category: intent.category,
        context: intent.context
      ).current_version
      
      # Call OpenAI with structured approach
      system_prompt = prompt.render(
        intent: intent.description,
        context: context.summary,
        capabilities: available_actions
      )
      
      response = OPENAI.chat.completions.create(
        model: "gpt-4o",
        messages: [
          { role: "system", content: system_prompt },
          { role: "user", content: build_response_request(intent, results) }
        ],
        temperature: 0.7
      )
      
      response.dig("choices", 0, "message", "content")
    end
  end
end
```

### 3. Intent Recognition & Mapping

```ruby
# app/services/literate/intent_interpreter.rb
module Literate
  class IntentInterpreter
    INTENT_SCHEMA = {
      type: "object",
      properties: {
        primary_intent: {
          type: "string",
          enum: [
            "create_dataset",
            "ingest_data", 
            "check_status",
            "explain_concept",
            "analyze_data",
            "generate_deliverable",
            "ask_question",
            "provide_feedback"
          ]
        },
        entities: {
          type: "array",
          items: { type: "string" }
        },
        parameters: {
          type: "object"
        },
        confidence: {
          type: "number"
        },
        requires_clarification: {
          type: "boolean"
        },
        suggested_actions: {
          type: "array",
          items: {
            type: "object",
            properties: {
              action: { type: "string" },
              params: { type: "object" }
            }
          }
        }
      }
    }
    
    def interpret(user_input, context)
      prompt = Prompt.find_by(key: 'intent_interpretation').current_version
      
      response = OPENAI.chat.completions.create(
        model: "gpt-4o",
        messages: [
          {
            role: "system",
            content: prompt.render(
              context: context,
              available_actions: ActionRegistry.all
            )
          },
          { role: "user", content: user_input }
        ],
        response_format: {
          type: "json_schema",
          json_schema: {
            name: "intent_interpretation",
            strict: true,
            schema: INTENT_SCHEMA
          }
        },
        temperature: 0
      )
      
      Intent.new(JSON.parse(response.dig("choices", 0, "message", "content")))
    end
  end
end
```

### 4. Context Management

```ruby
# app/models/conversation.rb
class Conversation < ApplicationRecord
  has_many :messages
  belongs_to :user, optional: true
  belongs_to :ingest_batch, optional: true
  
  # Store conversation state
  store_accessor :context, :current_dataset, :current_stage, 
                 :user_expertise_level, :preferred_detail_level
  
  def summary
    # Recent messages + current state
    {
      recent_messages: messages.recent(5).map(&:content),
      current_dataset: current_dataset,
      current_stage: current_stage,
      user_level: user_expertise_level || 'intermediate'
    }
  end
end

# app/models/message.rb
class Message < ApplicationRecord
  belongs_to :conversation
  
  enum role: { user: 0, assistant: 1, system: 2 }
  
  # Track message metadata
  store_accessor :metadata, :intent, :actions_taken, :entities_mentioned
end
```

### 5. Action Execution Framework

```ruby
# app/services/literate/action_executor.rb
module Literate
  class ActionExecutor
    def execute(intent)
      return unless intent.executable?
      
      results = []
      
      intent.suggested_actions.each do |action_spec|
        action = ActionRegistry.find(action_spec[:action])
        
        # Execute with explanation
        result = action.execute_with_explanation(
          params: action_spec[:params],
          conversation: @conversation
        )
        
        results << result
      end
      
      results
    end
  end
  
  # app/services/literate/actions/base_action.rb
  class BaseAction
    def execute_with_explanation(params:, conversation:)
      # Log what we're about to do
      explanation = explain_action(params)
      conversation.messages.create(
        role: 'system',
        content: "Executing: #{explanation}"
      )
      
      # Do it
      result = execute(params)
      
      # Explain what happened
      outcome = explain_outcome(result)
      
      { 
        action: self.class.name,
        explanation: explanation,
        result: result,
        outcome: outcome
      }
    end
    
    def explain_action(params)
      # Use prompt to explain what this action does
      prompt = Prompt.find_by(key: "explain_#{action_key}").current_version
      prompt.render(params)
    end
  end
end
```

### 6. Example Literate Interactions

```ruby
# Instead of scripted responses, actual understanding:

User: "I have a Postgres database with CHDS theses. Can you help me enliterate them?"

System: [Interprets: user wants to ingest data from database]
       [Recognizes: CHDS = Center for Homeland Defense and Security]
       [Understands: theses = academic documents]

Response: "I can help you enliterate the CHDS Master's theses from your Postgres 
          database. This is exciting - academic theses are rich with interconnected 
          ideas and evolving arguments that work beautifully in a knowledge graph.
          
          To get started, I'll need to understand your database structure. Could you
          share:
          1. The connection details (host, database name)
          2. The table or schema where the theses are stored
          3. What fields are available (title, author, year, abstract, full text?)
          
          Based on what you tell me, I'll create a custom extraction plan that 
          preserves the academic relationships and argument structures."

User: "The table is called 'theses' with columns: id, title, author, year, 
       advisor, abstract, full_text, keywords"

System: [Recognizes: complete thesis structure available]
       [Plans: SQL extraction → Pool mapping → Graph building]
       [Identifies: advisor relationships, keyword taxonomy, temporal patterns]

Response: "Perfect! This structure gives us everything needed for a comprehensive
          enliteration. Here's what I can extract:
          
          📚 **Pools I'll populate:**
          - **Ideas**: Thesis arguments, concepts from abstracts
          - **Manifest**: The theses themselves as documents  
          - **Experience**: Specific case studies and examples
          - **Relational**: Author-advisor relationships
          - **Evolutionary**: How topics evolved over years
          - **Practical**: Methodologies and recommendations
          
          🔗 **Relationships I'll map:**
          - Advisor → Student mentorship chains
          - Keyword evolution across years
          - Thematic clusters and schools of thought
          
          Shall I connect to your database now? I'll start with a small sample
          to show you the extraction pattern before processing everything."
```

### 7. Prompt Management Interface

```ruby
# app/controllers/prompts_controller.rb
class PromptsController < ApplicationController
  def index
    @prompts = Prompt.includes(:current_version, :prompt_versions)
  end
  
  def edit
    @prompt = Prompt.find(params[:id])
    @versions = @prompt.prompt_versions.order(created_at: :desc)
  end
  
  def create_version
    @prompt = Prompt.find(params[:id])
    @version = @prompt.prompt_versions.create(version_params)
    
    # Start A/B test if requested
    if params[:start_test]
      AbTestService.new(@prompt, @version).start
    end
  end
  
  def performance
    @prompt = Prompt.find(params[:id])
    @metrics = @prompt.performance_metrics
    @ab_tests = @prompt.ab_test_results
  end
end
```

### 8. Integration Points

```yaml
# config/prompts.yml - Initial prompt seeds
system:
  intent_interpretation:
    content: |
      You are the Enliterator's literate interface. Interpret the user's intent
      and map it to available system capabilities. Consider context: {{context}}
      Available actions: {{available_actions}}
      
  explain_concept:
    content: |
      Explain the concept of {{concept}} in the context of enliteration.
      User expertise level: {{user_level}}
      Use examples from: {{current_dataset}} if available.

interview:
  welcome:
    content: |
      Welcome! I'm Enliterator's literate interface. I understand natural language
      and can help you transform your data into knowledge. Tell me about your data
      in your own words - no need for technical commands.
      
  understand_data_source:
    content: |
      I understand you have {{data_type}}. Let me help you prepare it for
      enliteration. {{specific_guidance}}
```

### 9. Benefits of Literate Architecture

1. **Natural Interaction**: Users describe what they want in plain language
2. **Adaptive Responses**: System adjusts to user's expertise level
3. **Explainable Actions**: Every operation is explained in context
4. **Continuous Improvement**: Prompts can be updated without code changes
5. **Performance Tracking**: Know which prompts work best
6. **A/B Testing**: Test different phrasings and approaches
7. **Context Awareness**: Remembers conversation history and user preferences

### 10. Implementation Priority

1. **Phase 1**: Prompt model and management system
2. **Phase 2**: Basic literate engine with OpenAI integration  
3. **Phase 3**: Intent interpretation for core operations
4. **Phase 4**: Context management and conversation persistence
5. **Phase 5**: Action execution framework
6. **Phase 6**: Performance tracking and A/B testing
7. **Phase 7**: Full pipeline integration
8. **Phase 8**: Advanced features (learning, adaptation)

## The Literate Difference

**Before (Scripted):**
```
> 1
"You selected event data. Please provide CSV file."
```

**After (Literate):**
```
> "I want to analyze how Burning Man camps evolved after COVID"

"That's a fascinating question! The pandemic created a unique discontinuity 
in Burning Man's history - 2020 was cancelled, 2021 was virtual, and 2022 
saw a cautious return. 

To analyze camp evolution across this period, I'll need data from at least 
2018-2023 to establish pre-pandemic patterns and post-pandemic changes.

What data do you have available? I can work with:
- Placement databases (official camp locations and info)
- Camp directories or guides  
- Personal collections or surveys
- Photos with metadata

The richer the data, the more patterns we can discover - like which themes
persisted, which camps reformed with new identities, and how the geographic
clustering changed."
```

This is true literacy - understanding context, providing insights, and engaging in meaningful dialogue about the data.