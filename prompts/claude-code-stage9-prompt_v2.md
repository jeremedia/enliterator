# Stage 9 Implementation: Build on REAL Enliterated Knowledge

## Critical Understanding: Stage 9 Requires Complete Stages 0-8

**Stage 9 cannot exist without first processing the Enliterator codebase through the full pipeline.** There are no shortcuts, no canned responses, no regex patterns. The Knowledge Navigator shows REAL knowledge from the ACTUAL graph.

## Part A: Complete Pipeline Processing of Enliterator Itself (MANDATORY FIRST)

### Step 1: Prepare Enliterator Codebase for Ingestion

```bash
# Create a comprehensive bundle of Enliterator for processing
cd /path/to/enliterator
mkdir -p tmp/enliterator_corpus

# Copy EVERYTHING - source, docs, tests, configs
cp -r app/ tmp/enliterator_corpus/
cp -r docs/ tmp/enliterator_corpus/
cp -r lib/ tmp/enliterator_corpus/
cp -r test/ tmp/enliterator_corpus/
cp -r config/ tmp/enliterator_corpus/
cp README.md CLAUDE.md PROJECT_STATUS.md tmp/enliterator_corpus/
cp Gemfile Gemfile.lock package.json tmp/enliterator_corpus/

# Create the ingest bundle
cd tmp
tar -czf enliterator_corpus.tar.gz enliterator_corpus/
```

### Step 2: Run COMPLETE Pipeline Processing

```ruby
# This is NOT a test - this is the real processing that creates Meta-Enliterator

# 1. Create the Meta-Enliterator EKN
ekn = Ekn.create!(
  name: "Meta-Enliterator",
  description: "The Enliterator system's knowledge of itself",
  slug: "meta-enliterator"
)

# 2. Create ingest batch for the corpus
batch = IngestBatch.create!(
  ekn: ekn,
  name: "Enliterator Complete Codebase",
  source_path: "tmp/enliterator_corpus.tar.gz"
)

# 3. Run Stage 0-1: Intake and Rights
Ingest::IntakeJob.perform_now(batch.id)
Rights::AssignmentJob.perform_now(batch.id)

# 4. Run Stage 2-3: Lexicon and Pools
Lexicon::BootstrapJob.perform_now(batch.id)
Pools::ExtractionJob.perform_now(batch.id)

# 5. Run Stage 4-5: Graph Assembly
Graph::AssemblyJob.perform_now(batch.id)
Graph::IntegrityJob.perform_now(batch.id)

# 6. Run Stage 6: Embeddings (via Neo4j GenAI)
# This creates vector embeddings for EVERY node in the graph
Embedding::GenerationJob.perform_now(batch.id)

# 7. Run Stage 7: Literacy Scoring
Literacy::ScoringJob.perform_now(batch.id)
# VERIFY: Score must be >= 70 to proceed
raise "Insufficient literacy score" unless batch.reload.literacy_score >= 70

# 8. Run Stage 8: Generate Deliverables
Deliverables::GenerationJob.perform_now(batch.id)
```

### Step 3: Fine-Tune Model on the ACTUAL Knowledge Graph

```ruby
# Generate training data from the REAL graph
builder = FineTune::DatasetBuilder.new(batch_id: batch.id)
dataset = builder.call

# This creates training pairs from actual graph traversals:
# - "How do extraction services work?" → [actual path through service nodes]
# - "What connects lexicon to pools?" → [real relationships from graph]
# - "Show pipeline stages" → [actual stage nodes and connections]

# Train the model on this REAL data
trainer = FineTune::Trainer.new(
  dataset_path: dataset[:path],
  base_model: 'gpt-4.1-mini',
  suffix: 'meta-enliterator-v1'
)
job = trainer.call

# Wait for fine-tuning to complete
status = trainer.wait_for_completion(job[:job_id])
fine_tuned_model = status[:fine_tuned_model]

# Update settings to use this model
Setting.set('openai_model', fine_tuned_model)
```

### Step 4: Verify the Knowledge Graph Has Real Content

```cypher
// These queries should return ACTUAL data about Enliterator

// 1. Pipeline stages (should return 10 nodes)
MATCH (s:Stage) RETURN s.name, s.number ORDER BY s.number

// 2. Service relationships (should show actual service dependencies)
MATCH (s1:Service)-[r:CALLS|DEPENDS_ON]->(s2:Service)
RETURN s1.name, type(r), s2.name LIMIT 20

// 3. Ten Pool Canon (should have actual pool nodes)
MATCH (p:Pool) RETURN p.name, p.description

// 4. Documentation nodes (from processed markdown files)
MATCH (d:Document) WHERE d.type = 'markdown' 
RETURN d.title, d.path LIMIT 10

// 5. Check embedding vectors exist
MATCH (n) WHERE n.embedding IS NOT NULL 
RETURN count(n) as nodes_with_embeddings
// Should be > 1000 nodes
```

## Part B: NOW Build Stage 9 - Knowledge Navigator with REAL Data

### B.1: Query the Fine-Tuned Model for Intent Understanding

```ruby
# app/services/navigator/conversation_orchestrator.rb
class Navigator::ConversationOrchestrator
  def process(message, ekn)
    # 1. Use the FINE-TUNED model to understand intent
    intent = analyze_with_fine_tuned_model(message, ekn)
    
    # 2. Query the ACTUAL graph based on intent
    graph_data = query_real_knowledge_graph(intent, ekn)
    
    # 3. Generate response from REAL data
    response = generate_from_graph_data(graph_data, intent)
    
    # 4. Create visualization from ACTUAL nodes/edges
    visualization = build_visualization_from_real_data(graph_data)
    
    response
  end
  
  private
  
  def analyze_with_fine_tuned_model(message, ekn)
    # The fine-tuned model knows the graph structure
    client = OpenAI::Client.new
    response = client.chat(
      parameters: {
        model: Setting.get('openai_model'), # The fine-tuned model!
        messages: [
          {
            role: "system",
            content: "You are Meta-Enliterator. Analyze this query to determine what graph data to retrieve."
          },
          {
            role: "user", 
            content: message
          }
        ]
      }
    )
    
    # Model returns structured intent because it was trained on the graph
    JSON.parse(response.dig("choices", 0, "message", "content"))
  end
  
  def query_real_knowledge_graph(intent, ekn)
    case intent['query_type']
    when 'pipeline_flow'
      # Query ACTUAL pipeline stages from the graph
      ekn.neo4j_session.query(<<~CYPHER
        MATCH (s1:Stage)-[r:TRIGGERS]->(s2:Stage)
        WHERE s1.ekn_id = $ekn_id
        RETURN s1, r, s2
        ORDER BY s1.number
      CYPHER, ekn_id: ekn.id)
      
    when 'service_relationships'
      # Query ACTUAL service dependencies
      ekn.neo4j_session.query(<<~CYPHER
        MATCH path = (s1:Service)-[r*1..3]-(s2:Service)
        WHERE s1.ekn_id = $ekn_id
        AND s1.name CONTAINS $service_pattern
        RETURN path LIMIT 50
      CYPHER, ekn_id: ekn.id, service_pattern: intent['entity'])
      
    when 'concept_map'
      # Query ACTUAL Ten Pool Canon relationships
      ekn.neo4j_session.query(<<~CYPHER
        MATCH (p1:Pool)-[r]-(p2:Pool)
        WHERE p1.ekn_id = $ekn_id
        RETURN p1, r, p2
      CYPHER, ekn_id: ekn.id)
    end
  end
  
  def generate_from_graph_data(graph_data, intent)
    # Build response from ACTUAL data
    nodes = graph_data.map(&:first)
    relationships = graph_data.map(&:second)
    
    # Use the fine-tuned model to narrate the real data
    client = OpenAI::Client.new
    response = client.chat(
      parameters: {
        model: Setting.get('openai_model'),
        messages: [
          {
            role: "system",
            content: "Explain this graph data naturally. Reference actual nodes and relationships."
          },
          {
            role: "user",
            content: "Graph data: #{format_graph_for_llm(nodes, relationships)}"
          }
        ]
      }
    )
    
    response.dig("choices", 0, "message", "content")
  end
end
```

### B.2: Test Queries Against REAL Data

```ruby
# These queries should return ACTUAL information from the processed Enliterator codebase

ekn = Ekn.find('meta-enliterator')
orchestrator = Navigator::ConversationOrchestrator.new

# Test 1: Should describe ACTUAL pipeline stages from the graph
result = orchestrator.process("Show me how the pipeline stages connect", ekn)
# Response should mention real stages: "Stage 0 Intake flows to Stage 1 Rights..."
# Visualization should show actual stage nodes with connections

# Test 2: Should show REAL service dependencies  
result = orchestrator.process("How are the extraction services related?", ekn)
# Response should name actual services: "EntityExtractionService depends on OpenAI::Client..."
# Visualization should show actual service nodes from app/services/

# Test 3: Should display ACTUAL pool structure
result = orchestrator.process("Visualize the Ten Pool Canon", ekn)
# Response should describe real pools: "The Idea pool connects to Manifest through 'embodies'..."
# Visualization should show the 10 actual pool nodes

# Test 4: Should retrieve REAL documentation
result = orchestrator.process("What does STAGE_9_IN_PROGRESS.md say?", ekn)
# Response should quote from the ACTUAL document in the graph
```

### B.3: Visualize REAL Graph Data with D3.js

```javascript
// app/javascript/controllers/network_graph_controller.js
export default class extends Controller {
  static values = { 
    nodes: Array,      // ACTUAL nodes from Neo4j
    edges: Array,      // ACTUAL relationships
    focusId: String    // ACTUAL node ID to center on
  }
  
  connect() {
    this.renderRealGraph()
  }
  
  renderRealGraph() {
    // These are REAL nodes from the knowledge graph
    const nodes = this.nodesValue // e.g., [{id: "Stage:0", name: "Intake", type: "Stage"}, ...]
    const edges = this.edgesValue // e.g., [{source: "Stage:0", target: "Stage:1", type: "TRIGGERS"}]
    
    // Create force simulation with ACTUAL data
    this.simulation = d3.forceSimulation(nodes)
      .force("link", d3.forceLink(edges).id(d => d.id))
      .force("charge", d3.forceManyBody().strength(-300))
      .force("center", d3.forceCenter(this.width / 2, this.height / 2))
    
    // Color based on ACTUAL node types from the graph
    const nodeColors = {
      'Stage': '#4A90E2',      // Pipeline stages
      'Service': '#50E3C2',    // Ruby services
      'Pool': '#F5A623',       // Ten Pool Canon
      'Document': '#7ED321',   // Markdown docs
      'Model': '#BD10E0'       // Rails models
    }
    
    // Render with REAL data
    this.nodes = this.svg.selectAll(".node")
      .data(nodes)
      .enter().append("circle")
      .attr("r", d => d.importance || 10)
      .attr("fill", d => nodeColors[d.type] || '#999')
      .on("click", (event, d) => this.expandRealNode(d))
    
    // Labels show ACTUAL names
    this.labels = this.svg.selectAll(".label")
      .data(nodes)
      .enter().append("text")
      .text(d => d.name) // Real names like "ConversationOrchestrator", "Stage 7: Literacy"
  }
  
  expandRealNode(node) {
    // Fetch MORE real data about this node
    fetch(`/api/ekn/meta-enliterator/expand`, {
      method: 'POST',
      body: JSON.stringify({ node_id: node.id })
    })
    .then(response => response.json())
    .then(moreRealData => {
      // Add ACTUAL connected nodes to the visualization
      this.addNodes(moreRealData.nodes)
      this.addEdges(moreRealData.edges)
      this.simulation.restart()
    })
  }
}
```

## Part C: Integration Requirements

### C.1: Conversation Flow with Real Data

```erb
<!-- When user asks a question, it queries REAL data -->
<div data-controller="conversation">
  <!-- User: "How do extraction services work?" -->
  
  <!-- System queries the ACTUAL graph for extraction service nodes -->
  <!-- Finds: EntityExtractionService, RelationExtractionService, etc. -->
  <!-- Traces their REAL connections and dependencies -->
  
  <!-- Response uses ACTUAL data: -->
  <div class="assistant-message">
    The extraction services in Enliterator work through a coordinated pipeline:
    EntityExtractionService (app/services/pools/entity_extraction_service.rb) 
    processes text through OpenAI to identify entities for the Ten Pool Canon...
    [This comes from REAL graph traversal, not canned text]
  </div>
  
  <!-- Visualization shows ACTUAL service nodes and their relationships -->
  <div data-controller="network-graph"
       data-network-graph-nodes-value="[actual nodes from query]"
       data-network-graph-edges-value="[actual relationships]">
  </div>
</div>
```

### C.2: No Regex, No Patterns, No Canned Responses

```ruby
# ❌ NEVER DO THIS:
PATTERNS = {
  pipeline: /pipeline|stages/,  # NO!
  services: /service|extraction/ # NO!
}

CANNED_RESPONSES = {
  pipeline: "Enliterator has 9 stages..." # NO!
}

# ✅ ALWAYS DO THIS:
def process(message, ekn)
  # Ask the fine-tuned model what to query
  intent = ask_fine_tuned_model(message)
  
  # Query the ACTUAL graph
  data = query_neo4j(intent, ekn)
  
  # Generate response from REAL data
  narrate_actual_data(data)
end
```

## Verification Checklist

Before attempting Stage 9, verify:

### Prerequisites Complete
- [ ] Full Enliterator codebase processed through stages 0-8
- [ ] Neo4j contains > 1000 nodes about Enliterator
- [ ] Embeddings generated for all nodes
- [ ] Fine-tuned model trained on graph traversals
- [ ] Literacy score >= 70 for Meta-Enliterator

### Graph Contains Real Data
```cypher
// Run these queries - they should return substantial results
MATCH (n) WHERE n.ekn_id = 'meta-enliterator' RETURN count(n)  // > 1000
MATCH (s:Stage) RETURN count(s)  // Should be 10
MATCH (s:Service) RETURN count(s)  // > 50
MATCH (p:Pool) RETURN count(p)  // Should be 10
MATCH (d:Document) RETURN count(d)  // > 20
```

### Fine-Tuned Model Works
```ruby
# Test the model knows the graph
client = OpenAI::Client.new
response = client.chat(
  parameters: {
    model: Setting.get('openai_model'), # Should be fine-tuned model
    messages: [{
      role: "user",
      content: "What services exist in the pools module?"
    }]
  }
)
# Should return ACTUAL service names from the graph
```

## The Key Difference

### What Claude Code Built (Wrong)
- Regex patterns matching "pipeline" → canned response
- Hardcoded explanations about Enliterator
- Fake visualizations with made-up data

### What Should Be Built (Right)
- Fine-tuned model understands queries → queries real graph
- Responses generated from actual graph traversals
- Visualizations show real nodes and relationships

## Start Here (In Order)

1. **STOP** and run the full pipeline on Enliterator codebase
2. **VERIFY** the graph has real data (use queries above)
3. **TRAIN** the fine-tuned model on the graph
4. **THEN** build Stage 9 using real data

Without steps 1-3, Stage 9 is impossible. You're building a Knowledge Navigator for data that doesn't exist yet.

## Remember

**Meta-Enliterator is not a demo.** It's the actual Enliterator codebase processed through the pipeline, stored in Neo4j, with a fine-tuned model that understands it. Stage 9 visualizes THAT knowledge, not pretend knowledge.

When someone asks "How do extraction services work?", the system should:
1. Query the ACTUAL service nodes in the graph
2. Traverse their REAL relationships
3. Generate explanation from THAT data
4. Visualize THOSE nodes

This is the difference between a puppet show and a Knowledge Navigator.