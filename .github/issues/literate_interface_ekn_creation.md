# Literate Interface for EKN Creation - The Core Enliterator UX

## 🎯 Primary Goal
Build a **literate conversational interface** that guides users through understanding Enliterator and creating their own Enliterated Knowledge Navigators (EKNs) from their data collections.

## Vision Statement
Users should experience Enliterator as a **Knowledge Navigator** (like Apple's 1987 vision) that:
1. **Converses naturally** through voice or text
2. **Generates appropriate UIs** dynamically (forms, charts, maps, timelines)
3. **Guides visually** through the EKN creation process
4. **Presents information** in the most effective medium
5. **Adapts the interface** to match the user's needs and data

The Navigator should feel like a knowledgeable colleague who can:
- **Explain** what Enliterator does through words and visuals
- **Guide** users through creating EKNs with interactive assistance
- **Show** the enliteration process with live visualizations
- **Explore** knowledge graphs through dynamic interfaces
- **Deliver** insights in the most appropriate format

## Current Architecture Analysis

### ✅ What We've Built (Technical Foundation)

#### 1. Complete Pipeline Infrastructure
- **8-stage pipeline** fully implemented (Intake → Rights → Lexicon → Pools → Graph → Embeddings → Literacy → Deliverables)
- **Meta-EKN created**: System successfully enliterated itself (224 files, 75/100 score)
- **Database schema**: All tables and relationships in place
- **Background jobs**: Solid Queue for async processing

#### 2. Technical Routing Layer
- **Fine-tuned model** (`ft:gpt-4.1-mini-2025-04-14:chds:enliterator-v20250806:C1XuVw$K`)
- Understands canonical terms and MCP tool routing
- Returns structured JSON for system operations
- Could serve as internal routing/classification layer

#### 3. Admin Infrastructure
- Settings management UI
- Fine-tune job dashboard
- Model evaluation interface (side-by-side comparison)
- Webhook integration for real-time updates

#### 4. MCP Tool Specification
- Defined tools: `extract_and_link`, `search`, `fetch`, `bridge`, `location_neighbors`
- Contract specified in CLAUDE.md
- Ready for implementation once literate layer exists

### ❌ What's Missing (The Literate Layer)

#### 1. User-Facing Conversational Interface
- **No chat interface** for end users (only admin evaluation interface)
- **No onboarding flow** explaining what Enliterator is
- **No guided experience** for dropping data bundles
- **No progress narration** during pipeline processing
- **No conversational query** interface for exploring EKNs

#### 2. Literate Process Narration
- Pipeline runs silently without user feedback
- No explanations of what's happening at each stage
- No ability to ask questions during processing
- No narrative of discovered insights

#### 3. Interactive EKN Exploration
- No way to conversationally query the knowledge graph
- No natural language interface to MCP tools
- No guided discovery of relationships and patterns
- No storytelling from the graph paths

#### 4. Deliverable Generation Interface
- No conversational way to request specific outputs
- No explanation of available deliverables
- No customization through dialogue

## Proposed Architecture

### Three-Layer System

```
┌─────────────────────────────────────────┐
│   Literate Interface Layer (NEW)        │ ← What users interact with
│   - Natural conversation                │
│   - Process explanation                 │
│   - Guided EKN creation                │
│   - Knowledge exploration              │
└─────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│   Routing/Orchestration Layer          │ ← Our fine-tuned model
│   - Canonical term mapping             │
│   - MCP tool selection                 │
│   - Query normalization                │
│   - Intent classification              │
└─────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│   Execution Layer                      │ ← Existing pipeline
│   - 8-stage pipeline                   │
│   - Neo4j graph operations             │
│   - pgvector search                    │
│   - Deliverable generation             │
└─────────────────────────────────────────┘
```

### Key Insight
Our fine-tuned model that returns JSON routing IS valuable - but as the **middle layer**, not the user-facing layer. We need a truly literate model/system on top that:
- Speaks naturally about Enliterator concepts
- Guides users through the process
- Translates between human intent and system operations
- Tells stories from the data

## Implementation Plan

### Phase 1: Core Literate Interface
- [ ] Create main chat interface for users (not admin)
- [ ] Build conversation state management
- [ ] Implement literate system prompt that explains Enliterator
- [ ] Create onboarding conversation flow
- [ ] Add process narration during pipeline execution

### Phase 2: EKN Creation Flow
- [ ] Conversational data bundle upload
- [ ] Explain each pipeline stage as it runs
- [ ] Surface interesting discoveries during processing
- [ ] Handle questions during pipeline execution
- [ ] Celebrate completion with summary of what was created

### Phase 3: Knowledge Exploration
- [ ] Natural language query interface
- [ ] Story generation from graph paths
- [ ] Relationship explanation and visualization
- [ ] Pattern discovery narration
- [ ] Insight surfacing

### Phase 4: Integration
- [ ] Connect literate layer to routing layer (fine-tuned model)
- [ ] Implement MCP tools with natural language wrappers
- [ ] Add conversational deliverable generation
- [ ] Create feedback loops for continuous improvement

## Critical Questions to Resolve

1. **Literate Model Strategy**
   - Should we fine-tune a separate model for the literate layer?
   - Or use a base model with carefully crafted prompts?
   - How do we maintain the "voice" of Enliterator?

2. **User Journey**
   - What's the first thing a new user sees/experiences?
   - How do we explain enliteration to someone who's never heard of it?
   - What makes them want to create their own EKN?

3. **Process Visibility**
   - How much technical detail do we surface?
   - How do we make the pipeline stages understandable?
   - What insights do we highlight during processing?

4. **Knowledge Navigation**
   - How do users discover what questions they can ask?
   - How do we surface the structure of their knowledge graph?
   - What metaphors help explain the Ten Pool Canon?

## Success Metrics

### User Understanding
- Users can explain what Enliterator does after first conversation
- Users understand what an EKN is and why it's valuable
- Users can describe their data in terms of pools and relationships

### Creation Success
- Users successfully create EKNs without technical assistance
- Pipeline failures are explained in understandable terms
- Users feel guided and supported throughout the process

### Exploration Engagement
- Users discover insights they didn't expect
- Users ask progressively deeper questions
- Users share stories generated from their EKNs

## Technical Decisions Needed

1. **Frontend Framework**
   - Continue with Rails + Stimulus?
   - Add React/Vue for richer interactions?
   - Use ActionCable for real-time updates?

2. **Conversation Management**
   - Store full conversation history?
   - Implement conversation branching?
   - Support multiple concurrent sessions?

3. **Model Orchestration**
   - How to combine literate model + routing model?
   - When to use which model?
   - How to maintain context across models?

## Next Steps

### Immediate (This Week)
1. Design the user-facing chat interface
2. Create literate system prompts for explaining Enliterator
3. Build basic conversation flow for onboarding
4. Test with simple EKN creation scenario

### Short-term (Next 2 Weeks)
1. Implement process narration for pipeline stages
2. Create natural language wrappers for MCP tools
3. Build knowledge exploration conversations
4. Connect literate layer to routing layer

### Medium-term (Next Month)
1. Fine-tune dedicated literate model if needed
2. Implement full EKN creation flow
3. Build deliverable generation through conversation
4. Create comprehensive test suite

## Definition of Done

The literate interface is complete when:
1. A new user can have a conversation to understand Enliterator
2. They can create an EKN by dropping data and following guided conversation
3. They can explore their knowledge graph through natural language
4. They can generate deliverables through conversation
5. The entire experience feels like talking to a knowledgeable guide, not a technical system

## Open Questions for Discussion

1. Should the literate interface have a personality/character?
2. How technical should we allow conversations to become?
3. Should we support multiple conversation styles (expert vs. beginner)?
4. How do we handle ambiguous or unclear user requests?
5. What's the right balance between guidance and user control?

---

**Priority**: Critical - This IS the Enliterator user experience
**Effort**: Large (4-6 weeks for full implementation)
**Type**: Feature
**Labels**: literate-interface, ekn-creation, user-experience, core-functionality

## Related Issues
- #26 - Fine-Tune Dataset Builder (provides routing layer)
- #27 - Fine-Tune Trainer Service (creates routing model)
- #47 - OpenAI Settings Management (configuration for models)
- Model Evaluation Interface (testing ground for responses)

## Resources
- [Literate Technology Definition](https://docs.anthropic.com/en/docs/claude-code)
- [CLAUDE.md](../../CLAUDE.md) - System specification
- [Stage 8 Deliverables](../../docs/STAGE_8_DELIVERABLES_COMPLETE.md)
- [Project Status](../../docs/PROJECT_STATUS.md)