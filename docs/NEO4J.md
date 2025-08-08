# Neo4j Knowledge Graph - Complete Documentation

> **SINGLE SOURCE OF TRUTH** for all Neo4j configuration and usage in Enliterator

## 🔴 CRITICAL: Configuration

**Neo4j Desktop** is running with multi-database support enabled.

### The ONLY Configuration That Matters

**File**: `/config/initializers/neo4j.rb`
```ruby
Rails.application.config.neo4j = {
  url: ENV.fetch("NEO4J_URL", "bolt://100.104.170.10:8687"),  # Tailscale address
  username: ENV.fetch("NEO4J_USERNAME", ""),  # Not used - auth disabled
  password: ENV.fetch("NEO4J_PASSWORD", ""),  # Not used - auth disabled
  encryption: false,
  pool_size: 10
}

# Connection uses AuthTokens.none (authentication disabled)
@driver = Neo4j::Driver::GraphDatabase.driver(
  config[:url],
  Neo4j::Driver::AuthTokens.none,  # ← NO AUTHENTICATION
  encryption: false
)
```

### Connection Details
- **URL**: `bolt://100.104.170.10:8687` (port 8687, not default 7687)
- **Authentication**: DISABLED (uses `AuthTokens.none`)
- **Multi-database**: FULLY SUPPORTED
- **Access Method**: Neo4j Desktop application (NOT Homebrew, NOT Docker)

### DO NOT
- ❌ Create your own driver connections
- ❌ Use different URLs or ports
- ❌ Try to use username/password authentication
- ❌ Override these settings anywhere else

## 📐 Architecture

### Multi-Database Design
Each EKN (Enliterated Knowledge Navigator) gets its own isolated Neo4j database:

```
Neo4j Desktop Instance
├── neo4j (default database - for testing)
├── ekn-1 (EKN #1's knowledge)
├── ekn-2 (EKN #2's knowledge)
├── ekn-13 (Meta-Enliterator)
└── ekn-{id} (pattern for all EKNs)
```

### Why Database Isolation?
- **No data leakage** between knowledge domains
- **Independent schemas** per EKN
- **Clean backup/restore** per knowledge domain
- **Performance isolation** (separate indexes and caches)

### Database Naming Convention
```ruby
class Ekn < ApplicationRecord
  def neo4j_database_name
    # Prefer the EKN slug for readability and stability
    # Falls back to ID if slug is not present
    "ekn-#{slug.presence || id}"  # e.g., "ekn-meta-enliterator"
  end
end
```

## 🔧 Usage Patterns

### ALWAYS Use Graph::Connection

**Correct** ✅
```ruby
# Get the singleton driver
driver = Graph::Connection.instance.driver

# Open a session
session = driver.session(database: "ekn-13")
result = session.run("MATCH (n) RETURN count(n)")
session.close
```

**Wrong** ❌
```ruby
# NEVER create your own driver!
driver = Neo4j::Driver::GraphDatabase.driver(...)  # NO!
```

### Service Pattern
```ruby
class YourService
  def initialize(ekn)
    @ekn = ekn
    @database_name = ekn.neo4j_database_name
  end
  
  def perform
    driver = Graph::Connection.instance.driver
    session = driver.session(database: @database_name)
    
    # Your queries here
    result = session.run("MATCH (n) RETURN n LIMIT 10")
    
    session.close
  end
end
```

### Transaction Patterns

**Schema and Data Operations Must Be Separate**:
```ruby
# Schema operations (constraints, indexes)
session.write_transaction do |tx|
  tx.run("CREATE CONSTRAINT FOR (n:Entity) REQUIRE n.id IS UNIQUE")
end

# Data operations (nodes, relationships) - SEPARATE transaction!
session.write_transaction do |tx|
  tx.run("CREATE (n:Entity {id: 1, name: 'Test'})")
end
```

## 🚀 Stage 5: Graph Assembly

The Graph Assembly stage (Pipeline Stage 5) loads extracted entities into Neo4j.

### Key Components
- `Graph::AssemblyJob` - Main pipeline job
- `Graph::SchemaManager` - Creates constraints and indexes
- `Graph::NodeLoader` - Loads nodes from pools
- `Graph::EdgeLoader` - Creates relationships
- `Graph::Deduplicator` - Resolves duplicate entities

### Node Labels (Ten Pool Canon)
- `Idea` - Abstract concepts
- `Manifest` - Physical/digital artifacts
- `Experience` - Observations and testimonials
- `Relational` - Connections between entities
- `Evolutionary` - Changes over time
- `Practical` - Actions and practices
- `Emanation` - Influences and effects
- `Rights` - Provenance and permissions
- `Lexicon` - Canonical terms
- `Intent` - User goals and queries

## 🧬 Stage 6: Neo4j GenAI Integration

**STATUS**: Migrating from pgvector to Neo4j GenAI for embeddings

### What's Changing
- **Before**: Neo4j (graph) + pgvector (embeddings) = 2 databases
- **After**: Neo4j (graph + embeddings) = 1 unified database

### GenAI Capabilities
```cypher
-- Generate embeddings
CALL genai.vector.encodeBatch($texts, 'OpenAI', {
  token: $api_key,
  model: 'text-embedding-3-small'
})

-- Vector similarity search
CALL db.index.vector.queryNodes('embeddings', 10, $query_vector)
YIELD node, score
RETURN node, score

-- Hybrid query (structure + semantics)
CALL db.index.vector.queryNodes('embeddings', 10, $vector)
YIELD node as semantic_node, score
OPTIONAL MATCH (semantic_node)-[r]-(connected)
RETURN semantic_node, score, connected, type(r)
```

### Benefits
- Unified queries combining graph structure and semantic similarity
- No cross-database synchronization
- Embeddings isolated per EKN database
- Native vector indexes with cosine similarity

## 🛠 Common Operations

### Check Connection
```bash
rails runner 'puts Graph::Connection.instance.driver.verify_connectivity'
```

### Create EKN Database
```ruby
ekn = Ekn.create!(name: "My Knowledge Domain")
Graph::DatabaseManager.ensure_database_exists(ekn.neo4j_database_name)
```

### Query an EKN's Knowledge
```ruby
ekn = Ekn.find(13)  # Meta-Enliterator
service = Graph::QueryService.new(ekn.neo4j_database_name)
results = service.search_entities("pipeline stages")
```

### Database Statistics
```ruby
stats = Graph::DatabaseManager.get_database_statistics("ekn-13")
puts "Nodes: #{stats[:node_count]}"
puts "Relationships: #{stats[:relationship_count]}"
```

## 🔍 Troubleshooting

### Connection Failed
1. Check Neo4j Desktop is running
2. Verify URL: `bolt://100.104.170.10:8687`
3. Test: `nc -zv 100.104.170.10 8687`

### Empty Query Results
- Most common: Wrong database context
- Solution: Specify database explicitly
```ruby
session = driver.session(database: "ekn-13")  # Specify database!
```

### Transaction Errors
- Error: "Tried to execute Write query after executing Schema modification"
- Solution: Separate schema and data operations into different transactions

### Multi-Database Not Working
- Neo4j Desktop supports multi-database (Community Edition does not)
- Verify with: `SHOW DATABASES` in Neo4j Browser

## 📊 Testing & Validation

### Health Check Script
```bash
rails runner script/check_neo4j_health.rb
```

### Configuration Validation
```bash
rails runner script/validate_neo4j_config.rb
```

### Manual Testing
```ruby
# In rails console
driver = Graph::Connection.instance.driver
session = driver.session
result = session.run("RETURN 1 as test")
puts result.single['test']  # Should print: 1
session.close
```

## 📋 Migration Status

### Completed ✅
- Multi-database architecture implemented
- Each EKN gets isolated database
- Graph::Connection singleton pattern
- Schema/data transaction separation

### In Progress 🚧
- Neo4j GenAI embedding migration (Stage 6)
- Vector index creation per pool
- Hybrid query implementation

### Next Steps 📍
1. Complete Neo4j GenAI integration
2. Remove pgvector dependencies
3. Implement semantic-structural visualizations

## 🎯 Key Principles

1. **Single Configuration Source**: Only `/config/initializers/neo4j.rb` matters
2. **Always Use Singleton**: `Graph::Connection.instance.driver`
3. **Database Per EKN**: Complete isolation of knowledge domains
4. **No Authentication**: Uses `AuthTokens.none`
5. **Separate Transactions**: Schema ops separate from data ops

## 📚 Related Files

- `/config/initializers/neo4j.rb` - THE configuration
- `/app/services/graph/` - All graph services
- `/app/jobs/graph/assembly_job.rb` - Pipeline Stage 5
- `/app/models/ekn.rb` - Database naming logic

---

**Remember**: This document is the ONLY source of truth for Neo4j in Enliterator. If you see Neo4j information elsewhere that conflicts with this, THIS document is correct.
