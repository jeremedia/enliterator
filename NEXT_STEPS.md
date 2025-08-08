# Next Steps - Post-Pipeline Implementation

**Updated**: 2025-08-06  
**Status**: Core Pipeline 100% Complete ✅ | OpenAI Integration In Progress 🚧

## 📊 Current Focus: OpenAI Integration Overhaul

While the pipeline stages are complete, we're actively overhauling the OpenAI integration (Issue #47) to use the Responses API with database-backed settings management.

### In Progress Now:
- ✅ Settings Management System (database models, admin UI)
- ✅ Admin UI deployed at https://e.dev.domt.app/admin
- 🚧 Refactoring services to use OpenAI::Helpers::StructuredOutput::BaseModel
- 🚧 Implementing FineTune::DatasetBuilder (Issue #26)
- 🚧 Implementing FineTune::Trainer (Issue #27)

## Immediate Actions (Week 1)

### 1. Test the Complete Pipeline

```bash
# Run the full test suite
rails runner script/test_deliverables.rb

# Generate deliverables for a test batch
rails enliterator:deliverables:generate[1]

# Review outputs
ls -la tmp/deliverables/batch_1/
cat tmp/deliverables/batch_1/README.md
```

### 2. Process Real Data

```bash
# Ingest a real data bundle
rails enliterator:ingest[path/to/real_data.zip]

# Run through complete pipeline
rails enliterator:graph:sync
rails enliterator:embed:generate
rails enliterator:literacy:score[batch_id]

# If score ≥70, generate deliverables
rails enliterator:deliverables:generate[batch_id]
```

### 3. Deploy to Staging

```bash
# Set up production environment variables
cp .env.example .env.production
# Add production credentials

# Deploy to staging server
cap staging deploy

# Run migrations
cap staging rails:db:migrate

# Test pipeline on staging
cap staging rails:runner["script/test_deliverables.rb"]
```

## Short-term Priorities (Weeks 2-4)

### 1. MCP Server Implementation (Issue #23)

Create the Model Context Protocol server for AI interactions:

```ruby
# app/services/mcp/server.rb
module MCP
  class Server
    # Core tools implementation
  end
end

# app/controllers/api/mcp_controller.rb
class Api::McpController < ApplicationController
  # API endpoints for MCP tools
end
```

**Key Tools to Implement:**
- `extract_and_link` - Entity extraction with Structured Outputs
- `search` - Unified semantic + graph search
- `fetch` - Retrieve full records with relations
- `bridge` - Find connections between concepts
- `location_neighbors` - Spatial analysis
- `set_persona` / `clear_persona` - Style management

### 2. Fine-tuning Dataset Generation (Issue #26)

Extract training data from the knowledge graph:

```ruby
# app/services/fine_tune/dataset_builder.rb
module FineTune
  class DatasetBuilder
    def build_canonical_pairs
      # Extract canonical term mappings
    end
    
    def build_path_narrations
      # Generate path descriptions
    end
    
    def build_routing_examples
      # Create tool routing examples
    end
  end
end
```

**Dataset Types:**
- Canonical term mappings
- Path narrations
- Tool routing
- Query normalization
- Rights phrasing

### 3. Production Monitoring

Set up comprehensive monitoring:

```yaml
# config/monitoring.yml
metrics:
  - pipeline_runs_per_day
  - average_enliteracy_score
  - embedding_generation_time
  - deliverables_generation_time
  - api_costs_per_batch
  
alerts:
  - low_enliteracy_score: < 70
  - high_api_costs: > $10/batch
  - pipeline_failure: any_stage_fails
```

## Medium-term Goals (Month 2)

### 1. Dialogue System (Issue #30)

Build conversational interface:

```ruby
# app/services/dialogue/conversation_manager.rb
module Dialogue
  class ConversationManager
    def initialize(session_id)
      @session = load_or_create_session(session_id)
    end
    
    def process_turn(user_input)
      # Extract intent
      # Route to MCP tools
      # Generate response with citations
      # Update session state
    end
  end
end
```

### 2. Performance Optimization (Issue #36)

Focus areas:
- Neo4j query optimization
- Embedding search caching
- Batch processing improvements
- Database indexing

```ruby
# Performance targets
TARGETS = {
  search_p95: 800,  # ms
  embed_generation: 100,  # entities/second
  graph_sync: 500,  # nodes/second
  deliverables_generation: 300  # seconds total
}
```

### 3. Security Hardening (Issue #38)

Security checklist:
- [ ] API authentication (JWT/OAuth)
- [ ] Rate limiting
- [ ] Input validation
- [ ] SQL injection protection
- [ ] Rights enforcement audit
- [ ] Secrets management
- [ ] HTTPS enforcement
- [ ] CORS configuration

## Long-term Vision (Months 3-6)

### 1. Advanced Features

**Version Control for Datasets**
```ruby
# Track changes to enliterated datasets
class DatasetVersion < ApplicationRecord
  belongs_to :ingest_batch
  has_many :changes
  
  def diff_from(previous_version)
    # Generate changelog
  end
end
```

**Real-time Updates**
```ruby
# WebSocket support for live updates
class DatasetChannel < ApplicationCable::Channel
  def subscribed
    stream_from "dataset_#{params[:batch_id]}"
  end
  
  def receive(data)
    # Handle real-time entity updates
  end
end
```

**Collaborative Editing**
```ruby
# Multiple users editing same dataset
class CollaborativeSession < ApplicationRecord
  has_many :participants
  has_many :pending_changes
  
  def merge_changes
    # Conflict resolution
  end
end
```

### 2. API Documentation

Generate comprehensive API docs:

```ruby
# config/initializers/swagger.rb
Swagger::Docs::Config.register_apis({
  "1.0" => {
    api_extension_type: :json,
    api_file_path: "public/api/v1/",
    base_path: "https://enliterator.ai",
    clean_directory: false,
    attributes: {
      info: {
        "title" => "Enliterator API",
        "description" => "Transform data into enliterated datasets",
        "contact" => "api@enliterator.ai",
        "license" => "MIT"
      }
    }
  }
})
```

### 3. Client Libraries

Create SDKs for popular languages:

```javascript
// JavaScript/TypeScript SDK
import { Enliterator } from '@enliterator/sdk';

const client = new Enliterator({
  apiKey: process.env.ENLITERATOR_API_KEY
});

const dataset = await client.ingest({
  bundle: './data.zip'
});

const deliverables = await client.generateDeliverables({
  batchId: dataset.id,
  formats: ['json_ld', 'graphml']
});
```

## Quick Reference Commands

### Daily Operations
```bash
# Check pipeline status
rails enliterator:status

# Process new data
rails enliterator:ingest[data.zip]

# Score literacy
rails enliterator:literacy:score[batch_id]

# Generate deliverables
rails enliterator:deliverables:generate[batch_id]
```

### Monitoring
```bash
# Check embedding statistics
rails enliterator:embed:stats

# View batch API status
rails enliterator:embed:batch_status

# Calculate refresh schedule
rails enliterator:deliverables:refresh[batch_id]
```

### Testing
```bash
# Run all test scripts
for script in script/test_*.rb; do
  rails runner $script
done

# Test specific stage
rails runner script/test_deliverables.rb
```

## Environment Variables

Ensure these are set for production:

```bash
# Required
OPENAI_API_KEY=sk-...
DATABASE_URL=postgresql://...
NEO4J_URL=bolt://...
NEO4J_PASSWORD=...
REDIS_URL=redis://...

# Optional but recommended
OPENAI_MODEL=gpt-4.1-2025-04-14
OPENAI_EMBEDDING_MODEL=text-embedding-3-small
MONTHLY_REFRESH_BUDGET=100
BATCH_API_ENABLED=true
```

## Success Metrics

Track these KPIs:

| Metric | Target | Current |
|--------|--------|---------|
| Pipeline Success Rate | >95% | - |
| Average Enliteracy Score | >80 | - |
| Deliverables Generation Time | <5 min | - |
| API Cost per Batch | <$5 | - |
| User Satisfaction | >4.5/5 | - |

## Support & Resources

- **Documentation**: `/docs/` directory
- **Test Scripts**: `/script/test_*.rb`
- **GitHub Issues**: https://github.com/jeremedia/enliterator/issues
- **Spec**: `/docs/enliterator_enliterated_dataset_literate_runtime_spec_v_1.md`

## Celebrate! 🎉

The core pipeline is complete. You've built a system that can:
- Transform raw data into structured knowledge
- Build navigable knowledge graphs
- Generate embeddings for retrieval
- Assess dataset quality
- Produce comprehensive deliverables
- Export to multiple formats
- Self-optimize operations

**Congratulations on reaching 100% pipeline completion!**

---

*This document will be updated as post-pipeline features are implemented.*