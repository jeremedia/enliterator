# Claude Code Prompt for Stage 9 Development

## Your Mission: Build Stage 9 - The Knowledge Navigator Interface

You are building **Stage 9** of the Enliterator pipeline - the stage that transforms technical infrastructure into actual Knowledge Navigators that users can interact with. This is THE PRODUCT. Without Stage 9, Enliterator is a car parts factory that never assembles a car.

## Vision: Apple's Knowledge Navigator (1987) Made Real in 2025

Watch this first if unfamiliar: [Apple Knowledge Navigator Concept (1987)](https://www.youtube.com/watch?v=umJbmqHHH8s)

We're building exactly that - a conversational interface where users:
- **Talk naturally** to their data (voice or text)
- **See dynamic visualizations** generated on the fly
- **Get answers** through the most appropriate medium
- **Feel like** they're talking to a knowledgeable colleague

## Current State: 89% Complete (Missing THE PRODUCT)

**✅ Stages 0-8 COMPLETE** (Technical Infrastructure):
- Knowledge graph with 100+ nodes from Enliterator's own codebase
- Fine-tuned model that understands routing (but returns JSON - wrong for users!)
- Embeddings, search, MCP tools all working
- Pipeline processes data successfully

**❌ Stage 9 NOT STARTED** (The Actual Product):
- No conversational interface
- No dynamic UI generation
- No voice interaction
- No way for users to actually use any of it!

## What You're Building in Stage 9

### 1. Conversational Interface (Primary)
```
NOT THIS (Current):
User input → JSON response: {"canonical": "term", "mcp": "tool"}

BUT THIS (Goal):
User: "What is Enliterator?"
Navigator: "I'm Enliterator, a system that transforms data into Knowledge Navigators. 
           Let me show you how I work..." 
           [Generates interactive pipeline visualization]
```

### 2. Dynamic UI Generation
The Navigator should create interfaces as needed:
- User asks about relationships → Generate network graph
- User asks about timeline → Generate temporal visualization  
- User needs to input data → Generate appropriate form
- User wants comparison → Generate table or chart

### 3. Voice Interaction
- Web Speech API for voice input/output
- Natural conversation flow
- Synchronized with visual elements

### 4. Natural Language Wrappers
All technical operations wrapped in conversation:
- MCP tools never exposed as JSON
- Graph queries presented as insights
- Errors explained helpfully

## Concrete First Steps

### Step 1: Create Basic Conversational UI
Start with `app/views/navigator/index.html.erb`:
- Chat interface (NOT admin panel)
- User-facing (NOT technical)
- Natural conversation (NOT JSON responses)

### Step 2: Implement Navigator Controller
Create `app/controllers/navigator_controller.rb`:
```ruby
class NavigatorController < ApplicationController
  def index
    # The main Knowledge Navigator interface
  end
  
  def converse
    # Handle user input and generate natural responses
    # This wraps all the technical infrastructure
  end
end
```

### Step 3: Build the Conversation Service
Create `app/services/navigator/conversation_manager.rb`:
```ruby
class Navigator::ConversationManager
  def process_input(user_text)
    # 1. Understand intent (can use fine-tuned model internally)
    # 2. Generate natural response (NOT JSON)
    # 3. Determine if UI generation needed
    # 4. Return conversational response + UI specs
  end
end
```

### Step 4: Add Dynamic UI Components
Create Stimulus controllers for dynamic interfaces:
- `navigator_controller.js` - Main conversation flow
- `dynamic_ui_controller.js` - Generates visualizations
- `voice_controller.js` - Handles speech I/O

## Critical Requirements

### MUST Have
- Users can have natural conversations about Enliterator
- Technical complexity completely hidden
- Dynamic UIs appear naturally
- Feels like talking to a knowledgeable colleague

### Must NOT Have
- ❌ JSON responses shown to users
- ❌ Technical terminology in conversation
- ❌ Static dashboards or forms
- ❌ Admin-style interfaces

## Key Documents to Read

1. **STAGE_9_KNOWLEDGE_NAVIGATOR.md** - Complete Stage 9 specification
2. **LITERATE_INTERFACE_MISSING.md** - Why Stage 9 is critical
3. **STAGE_9_INTEGRATION.md** - How Stage 9 completes the pipeline
4. **GitHub Issue #49** - Literate Interface requirements
5. **GitHub Issue #30** - Knowledge Navigator Interface details

## Success Criteria

You'll know Stage 9 is working when:

1. **First Contact Success**
   - New user can understand what Enliterator is through conversation
   - No documentation needed

2. **Natural Interaction**
   - User: "Show me how concepts connect"
   - Navigator: Generates interactive graph with explanation
   - NOT: Returns JSON with graph data

3. **Voice Works**
   - User can speak questions
   - Navigator responds with voice + visuals

4. **Dynamic UI**
   - Appropriate interfaces appear automatically
   - No manual UI selection needed

## Example Interaction to Build Towards

```
User: "Hello"

Navigator: "Welcome! I'm your Enliterator Knowledge Navigator. I help transform 
           data into conversational experiences like this one. Would you like to 
           see how I work, or do you have data you'd like to explore?"

User: "Show me how you work"

Navigator: "I'll demonstrate with my own architecture. I process data through 
           9 stages..."
           
[Generates animated pipeline visualization]

Navigator: "Each dataset becomes its own Knowledge Navigator - a conversational 
           guide like me. You can drop any collection of documents, and I'll 
           create one specifically for that data. Shall we try with your data?"

User: "What kind of data can you handle?"

Navigator: "I work best with collections of related documents - research notes, 
           business documents, creative works, technical documentation. Let me 
           show you some examples..."
           
[Generates example gallery with different data types]
```

## Remember: Stage 9 IS the Product

Without Stage 9:
- Enliterator is unusable by actual users
- All technical infrastructure is wasted
- The vision remains unfulfilled

With Stage 9:
- Every dataset becomes a Knowledge Navigator
- Users experience magic, not machinery
- Apple's 1987 vision becomes reality

## Start Here

1. Create the navigator routes
2. Build the basic conversational UI
3. Implement natural language processing (wrap the routing model)
4. Add one dynamic UI component (start with charts or forms)
5. Test with a simple conversation

Don't build more infrastructure. Build the interface that makes the existing infrastructure usable.

**Your North Star**: Would someone from 1987 watching Apple's Knowledge Navigator video recognize what you're building as the same vision?

---

*Remember: You're not building a chatbot or a dashboard. You're building a Knowledge Navigator - a multimodal conversational interface that makes data literate.*