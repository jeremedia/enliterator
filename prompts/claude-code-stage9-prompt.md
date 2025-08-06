# Build Stage 9: Transform Meta-Enliterator Chat into Knowledge Navigator

## Prerequisites: Add Meaningful Names to EKNs (15 minutes)

Before we start Stage 9, let's make EKNs addressable by meaningful slugs instead of database IDs. This will make all our work clearer.

### Quick Implementation

1. **Add friendly_id gem**
```bash
bundle add friendly_id
rails generate friendly_id
rails db:migrate
```

2. **Update EKN model**
```ruby
# app/models/ekn.rb
class Ekn < ApplicationRecord
  extend FriendlyId
  friendly_id :name, use: [:slugged, :finders, :history]
  
  # :slugged - generates URL-safe slugs
  # :finders - allows Ekn.find() to work with slugs OR ids
  # :history - tracks slug changes if you rename an EKN
  
  # Now you can do:
  # Ekn.find('meta-enliterator')  # works!
  # Ekn.find(13)                  # also works!
  # ekn.friendly_id               # => "meta-enliterator"
  
  # ... existing code ...
end
```

3. **Update existing Meta-Enliterator**
```ruby
# In rails console or migration
ekn = Ekn.find(13)
ekn.update!(name: "Meta-Enliterator", slug: "meta-enliterator")

# Update any other existing EKNs with meaningful names
```

4. **Update references in code**
- Change `ekn_id: 13` to `ekn_id: 'meta-enliterator'`
- Controllers can use standard `Ekn.find(params[:id])` - it handles both slugs and IDs!
- Routes work automatically with slugs in URLs

### Why This Matters
- "Query meta-enliterator for pipeline stages" is clearer than "Query ekn-13"
- AI assistants understand semantic names better
- URLs become meaningful: `/ekn/meta-enliterator/chat`
- Aligns with "literate computing" principles

Once complete, we can refer to Meta-Enliterator by name throughout Stage 9.

---

## Current State Assessment

I'm completing Stage 9 of Enliterator. The Meta-Enliterator (EKN #13, now addressable as 'meta-enliterator') is live with:
- ✅ 5 accumulated batches of knowledge about the Enliterator codebase
- ✅ Working chat that can answer questions about the system
- ✅ Neo4j graph with ~2,000 nodes (services, models, docs, concepts)
- ❌ NO visualizations - users can only read text responses
- ❌ NO dynamic UI - everything is static conversation

**Today's Mission:** Make Meta-Enliterator SHOW its knowledge, not just tell about it.

## Test Case: Meta-Enliterator as First Navigator

Meta-Enliterator ('meta-enliterator') will be our proving ground. It should help users understand Enliterator by:
- Showing the pipeline stages as an interactive flow diagram
- Visualizing service dependencies as a network graph  
- Displaying the Ten Pool Canon as an explorable concept map
- Revealing code relationships when asked "How does X work?"

## Key Files to Understand Current State

```
app/models/ekn.rb                    # EKN model with friendly_id support
app/controllers/navigator/conversations_controller.rb  # Current chat
app/services/mcp/search_tool.rb     # How we query the graph now
/docs/STAGE_9_IN_PROGRESS.md        # Honest status (30% complete)
/docs/ekn-dynamic-ui-spec.md        # UI patterns to implement
```

## Today's Vertical Slice: Network Graph Visualization

### Concrete Test Queries (Must Work by End of Session)

1. "Show me how the pipeline stages connect" 
   → Should render interactive flow diagram of stages 0-9

2. "How are the extraction services related?"
   → Should show network graph of service dependencies

3. "Visualize the Ten Pool Canon"
   → Should display pools as connected concept nodes

4. "What connects the MCP tools to the graph?"
   → Should reveal the architectural relationships

### Implementation Approach

#### 1. Extend Conversation to Detect Visualization Needs

```ruby
# app/services/navigator/conversation_orchestrator.rb
class Navigator::ConversationOrchestrator
  def process(message, ekn_slug)
    ekn = Ekn.find(ekn_slug)  # Works with 'meta-enliterator' or 13!
    
    # Use the fine-tuned model to understand intent
    intent = analyze_with_model(message, ekn)
    
    # If visualization needed, prepare both text AND visual response
    if intent[:needs_visualization]
      {
        text_response: generate_narrative(intent),
        visualization: {
          type: intent[:viz_type],  # :network, :timeline, :tree
          data: fetch_graph_data(intent[:query], ekn),
          anchor: intent[:focal_entity]  # What to center on
        }
      }
    end
  end
  
  private
  
  def fetch_graph_data(query_spec, ekn)
    # Query Neo4j for the specific subgraph needed
    # Return nodes + relationships in D3-ready format
  end
end
```

#### 2. Create Visualization Canvas Component

```javascript
// app/javascript/navigator/knowledge_canvas.js
import * as d3 from 'd3';

class KnowledgeCanvas {
  constructor(container) {
    this.container = container;
    this.visualizations = new Map(); // Can show multiple
  }
  
  addNetworkGraph(data, options = {}) {
    // Progressive disclosure:
    // 1. Show immediate neighbors first
    // 2. Expand on click
    // 3. Always maintain context to conversation
    
    const viz = new NetworkVisualization(data, {
      initialDepth: 2,
      centerOn: options.anchor,
      ...options
    });
    
    this.visualizations.set(viz.id, viz);
    viz.render(this.container);
    
    // Return handle for conversation to reference
    return viz.id;
  }
}
```

#### 3. Neo4j Query Patterns for Meta-Enliterator

```cypher
// Get pipeline stage connections
MATCH path = (s:Service)-[:CALLS|TRIGGERS*1..3]->(s2:Service)
WHERE s.stage IS NOT NULL
RETURN path

// Get service dependency network
MATCH (s:Service)-[r:USES|DEPENDS_ON|CALLS]->(s2:Service)
WHERE s.name CONTAINS $servicePattern
RETURN s, r, s2 LIMIT 50

// Get Ten Pool Canon relationships  
MATCH (p:Pool)-[r:FLOWS_TO]->(p2:Pool)
RETURN p, r, p2
```

### Success Metrics (Measure at End of Session)

1. **Accumulation Test:** Ask about a service added in batch 1 vs batch 5 - both should appear in the same visualization

2. **Interaction Test:** Click a node → shows details without losing conversation context

3. **Performance Test:** 100-node graph renders in < 500ms

4. **Grounding Test:** Every visual element traces back to a Neo4j node/relationship

### Integration Points

- Extend existing `Navigator::ConversationsController` (don't replace)
- Reuse `MCP::SearchTool` queries where possible
- Maintain conversation history in database
- Use Stimulus for progressive enhancement
- Use 'meta-enliterator' slug everywhere (`:finders` addon makes this seamless)

### What NOT to Do

❌ Don't use regex patterns for intent detection  
❌ Don't create a separate "visualization mode"  
❌ Don't require users to use special commands  
❌ Don't show raw Neo4j responses  
❌ Don't lose conversation thread when showing visuals

### The Litmus Test

After implementing, ask Meta-Enliterator:
> "I'm new to Enliterator. Can you show me how the system processes data?"

The response should:
1. Start explaining in text
2. Naturally generate a pipeline flow diagram
3. Allow clicking stages to explore deeper
4. Maintain conversational explanation alongside visuals

## Remember the Vision

We're making Meta-Enliterator into the system's own Knowledge Navigator. When complete, it should feel like pair programming with someone who knows the codebase perfectly and can sketch diagrams while explaining.

The technology should disappear. Only the knowledge should shine through. Even our identifiers should be meaningful - we talk about "meta-enliterator" not "ekn-13".

## Start Here

1. Verify friendly_id is working: Both `Ekn.find('meta-enliterator')` and `Ekn.find(13)` should work
2. Run Meta-Enliterator locally and try the test queries
3. Examine what data comes back from current MCP::SearchTool
4. Implement the ConversationOrchestrator enhancement
5. Build the simplest possible D3 network graph
6. Connect them together
7. Iterate until it feels magical

Let's make Meta-Enliterator SHOW what it knows! 🚀