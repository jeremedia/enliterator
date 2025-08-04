# Enliterator

A Rails 8 application that transforms drop-off data collections into **enliterated datasets** with **literate runtime** capabilities. Enliterator creates knowledge graphs that can converse intelligently about their contents, show reasoning paths, cite sources, and produce multimodal deliverables.

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
- **PostgreSQL** for operational data
- **Neo4j** for knowledge graph
- **pgvector** for embeddings and retrieval
- **Redis** for caching
- **OpenAI API** for extraction and fine-tuning
- **Docker** for development environment

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
# OpenAI Configuration
OPENAI_API_KEY=your-api-key
OPENAI_MODEL=gpt-4-turbo-preview
OPENAI_MODEL_ANSWER=gpt-4
OPENAI_FT_BASE=gpt-4o-mini
OPENAI_FT_MODEL=ft:gpt-4o-mini:your-org:enliterator-canon-v1

# Database URLs
DATABASE_URL=postgresql://localhost/enliterator_development
REDIS_URL=redis://localhost:6379
NEO4J_URL=bolt://localhost:7687
VECTOR_DB_URL=postgresql://localhost/enliterator_development

# Storage
STORAGE_BUCKET=enliterator-dev
```

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

# Build fine-tune dataset
bin/rails enliterator:fine_tune:build

# Run evaluation suite
bin/rails enliterator:evaluate
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