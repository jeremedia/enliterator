# Enliterator

A Rails 8 application that transforms data collections into **Enliterated Knowledge Navigators (EKNs)** - persistent, growing conversational interfaces to your data, inspired by Apple's 1987 Knowledge Navigator vision.

## The Vision: Knowledge Navigators

Enliterator doesn't just process data - it creates **Knowledge Navigators**. Each dataset becomes a knowledgeable colleague you can:
- **Converse with naturally** using voice or text
- **See data visualized dynamically** as graphs, timelines, maps, and charts
- **Explore interactively** through clicking, zooming, and filtering
- **Learn from progressively** as they accumulate knowledge over time

**Current Status**: Pipeline complete (Stages 0-8), Knowledge Navigator interface 30% complete (Stage 9)

## What is Enliteracy?

**Literate technology** treats data as a partner in meaning rather than a passive store. It:
- Converses in natural language
- Shows reasoning paths and sources
- Adapts to user intent and constraints
- Produces deliverables (webpages, PDFs, maps, timelines, etc.)

**Enliteracy** is the process that makes a dataset literate by:
- Modeling it into pools of meaning with explicit flows
- Adding rights, provenance, and canonical lexicon
- Enabling the system to answer *why*, *how*, and *what's next*, not only *what*

## Core Architecture: EKN Model

Each **Enliterated Knowledge Navigator (EKN)** is a persistent entity that:
- **Maintains identity** across sessions (e.g., "Chicken Knowledge", "Recipe Collection")
- **Accumulates knowledge** through multiple data imports (IngestBatches)
- **Shares a database** among all its batches for true knowledge growth
- **Remembers conversations** and learning patterns
- **Grows smarter** with each interaction and data addition

The Meta-Enliterator (EKN #13) is Enliterator's understanding of itself - it guides users in creating their own Knowledge Navigators.

## Core Features

### Zero-Touch Pipeline
Drop a data bundle and the system automatically:
1. **Intake** - Discovers, hashes, and partitions files
2. **Rights & Provenance** - Triages licenses and consent
3. **Lexicon Bootstrap** - Creates canonical terms and normalizations
4. **Pool Filling** - Extracts entities using the Ten Pool Canon
5. **Graph Assembly** - Builds Neo4j knowledge graph
6. **Retrieval Indices** - Creates pgvector embeddings
7. **Literacy Scoring** - Evaluates completeness and gaps
8. **Deliverables** - Generates evaluation bundles

### Ten Pool Canon
The portable contract for meaning:
1. **Idea** - Principles, theories, intents (the *why*)
2. **Manifest** - Concrete instances and artifacts (the *what*)
3. **Experience** - Lived outcomes and perceptions
4. **Relational** - Connections, lineages, networks
5. **Evolutionary** - Change over time
6. **Practical** - How-to and tacit knowledge
7. **Emanation** - Ripple effects and influence
8. **Provenance & Rights** - Source, attribution, consent
9. **Lexicon & Ontology** - Definitions and controlled vocabulary
10. **Intent & Task** - User requests and fulfillment

### MCP Server Tools
- `extract_and_link` - Extract entities with OpenAI Structured Outputs
- `search` - Unified semantic + graph search with rights filtering
- `fetch` - Retrieve full records with relations
- `bridge` - Find paths between concepts
- `location_neighbors` - Spatial analysis (when applicable)
- `set_persona` / `clear_persona` - Style customization

### Delivery Adapters
Transform grounded answers into:
- Webpages
- Markdown/PDF documents
- Tables/CSV files
- Maps and timelines
- Outlines and storyboards
- Voice scripts

## Technology Stack

- **Rails 8** with Solid Queue, Solid Cache, Solid Cable
- **PostgreSQL 16+** for operational data with pgvector extension
- **Neo4j Desktop** for knowledge graph (see `/docs/NEO4J.md` for configuration)
- **pgvector** with neighbor gem for embeddings (HNSW index)
- **Redis** for caching and queue management
- **OpenAI Ruby gem v0.16.0** with Responses API and Structured Outputs
- **Docker Compose** for development services
- **Admin UI** for settings management (https://e.dev.domt.app/admin)

## Quick Start

### Prerequisites
- Ruby 3.3+
- PostgreSQL 16+
- Docker and Docker Compose
- OpenAI API key

### Installation

```bash
# Clone the repository
git clone https://github.com/yourusername/enliterator.git
cd enliterator

# Install dependencies
bundle install

# Setup databases
bin/setup

# Start all services with Docker Compose
docker compose up -d

# Run database migrations
bin/rails db:create db:migrate

# Start the development server
bin/dev
```

### Environment Variables

Create a `.env` file:

```env
# OpenAI Configuration (managed via Admin UI)
OPENAI_API_KEY=your-api-key

# Database URLs
DATABASE_URL=postgresql://localhost/enliterator_development
REDIS_URL=redis://localhost:6379
# Neo4j configuration - see /docs/NEO4J.md for complete documentation
NEO4J_URL=bolt://100.104.170.10:8687

# Optional (defaults provided)
STORAGE_BUCKET=enliterator-dev
```

**Note**: OpenAI models and settings are now managed via the Admin UI at https://e.dev.domt.app/admin, not environment variables.

## Usage

### Ingest a Data Bundle

```bash
# Process a ZIP file or directory
bin/rails enliterator:ingest[path/to/data.zip]

# Monitor pipeline progress
bin/rails enliterator:pipeline:status
```

### Query the Knowledge Graph

```ruby
# In Rails console
result = Mcp::SearchTool.new.call(
  query: "What embodies Radical Inclusion?",
  require_rights: "public",
  top_k: 10
)
```

### Generate Deliverables

```ruby
# Create a markdown report
adapter = Delivery::MarkdownAdapter.new
report = adapter.render(
  content: search_results,
  title: "Radical Inclusion Analysis",
  include_citations: true
)
```

## Development

### Running Tests

```bash
# Run all tests
bin/rails test

# Run specific test suite
bin/rails test test/services/ingest/**/*_test.rb

# Run system tests
bin/rails test:system
```

### Code Quality

```bash
# Run RuboCop
bundle exec rubocop

# Run ERB linter
bundle exec erblint --lint-all
```

### Pipeline Operations

```bash
# Sync graph database
bin/rails enliterator:graph:sync

# Refresh embeddings
bin/rails enliterator:embed:refresh

# Build fine-tune dataset (NEW)
bin/rails enliterator:fine_tune:build[batch_id]

# Create and monitor fine-tune job (NEW)
bin/rails runner "FineTune::Trainer.new(dataset_path: 'path/to/train.jsonl').call"

# Run evaluation suite
bin/rails enliterator:evaluate
```

### Fine-Tuning Capabilities (NEW)

The system can now generate training datasets and fine-tune OpenAI models:

```ruby
# Generate training data from knowledge graph
builder = FineTune::DatasetBuilder.new(batch_id: 1)
dataset = builder.call

# Train a fine-tuned model
trainer = FineTune::Trainer.new(
  dataset_path: dataset[:path],
  base_model: 'gpt-4.1-mini'
)
job = trainer.call

# Check training status
status = FineTune::Trainer.check_status(job[:job_id])
```

## Architecture

See [CLAUDE.md](CLAUDE.md) for detailed implementation guidance.

### Service Modules
- `Ingest/` - Bundle discovery and MIME routing
- `Rights/` - Rights and provenance management
- `Lexicon/` - Canonical terms and normalization
- `Pools/` - Ten Pool Canon models
- `Graph/` - Neo4j operations and path textization
- `Embedding/` - pgvector index management
- `Runtime/` - Q&A orchestration and gap tracking
- `MCP/` - Tool server implementation
- `Models/` - Fine-tune dataset generation

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Write tests for your changes
4. Ensure all tests pass and code meets style guidelines
5. Commit your changes (`git commit -m 'Add amazing feature'`)
6. Push to the branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

Built with Rails 8 and powered by OpenAI for intelligent data processing.