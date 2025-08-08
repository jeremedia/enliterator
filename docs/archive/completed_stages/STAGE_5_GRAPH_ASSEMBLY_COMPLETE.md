# Stage 5: Graph Assembly - Implementation Complete

## Overview
Stage 5 of the Enliterator pipeline has been successfully implemented. This stage takes the extracted entities and relationships from Stage 4 (Pool Filling) and assembles them into a Neo4j knowledge graph.

## What Was Implemented

### 1. Core Job
- **Graph::AssemblyJob** - Main orchestrator for the graph assembly process
  - Sets up Neo4j schema (constraints and indexes)
  - Loads nodes from all pools
  - Creates relationships using the verb glossary
  - Resolves duplicates
  - Removes orphaned nodes
  - Verifies graph integrity

### 2. Service Classes

#### Graph::SchemaManager
- Creates unique constraints on node IDs
- Creates existence constraints for required properties (rights_id, repr_text, time fields)
- Creates indexes for commonly queried properties
- Handles all node types from the Ten Pool Canon

#### Graph::NodeLoader
- Loads nodes from all ActiveRecord models into Neo4j
- Converts model attributes to Neo4j node properties
- Handles all required pools (Idea, Manifest, Experience, etc.)
- Supports optional pools (Actor, Spatial, Evidence, Risk, Method)
- Uses MERGE to handle potential duplicates

#### Graph::EdgeLoader
- Creates relationships based on the Relation Verb Glossary
- Automatically creates reverse edges where defined
- Handles symmetric relationships (co_occurs_with, adjacent_to)
- Links all entities to their ProvenanceAndRights nodes
- Maps ActiveRecord associations to graph relationships

#### Graph::Deduplicator
- Identifies duplicate nodes based on matching properties
- Merges duplicates while preserving relationships
- Combines properties from duplicates intelligently
- Tracks all merge operations for audit

#### Graph::OrphanRemover
- Identifies nodes without required relationships
- Removes orphaned nodes (except allowed isolated types)
- Preserves legitimate isolated nodes (ProvenanceAndRights, Lexicon)
- Protects recently created nodes from premature removal

#### Graph::IntegrityVerifier
- Verifies all nodes have required properties
- Checks rights pointers are present
- Validates time fields (valid_time_start or observed_at)
- Ensures relationships follow verb glossary rules
- Verifies reverse edges exist where required
- Checks canonical names for path textization

#### Graph::PathTextizer
- Converts graph paths to human-readable sentences
- Uses canonical names and verb display names
- Supports both technical and narrative formats
- Example: "Idea(Radical Inclusion) → embodies → Manifest(Welcome Station)"
- Narrative: "the idea of 'Radical Inclusion' embodies the manifestation 'Welcome Station'"

### 3. Updated Services
- **Graph::LexiconWriter** - Now fully implemented to sync lexicon entries to Neo4j
  - Creates Lexicon nodes with all properties
  - Creates NORMALIZES relationships to entities
  - Links related terms (BROADER_THAN, NARROWER_THAN, RELATED_TO)

### 4. Database Migration
- Added `graph_assembly_stats` (JSONB) to IngestBatch
- Added `graph_assembled_at` timestamp to IngestBatch

### 5. Tests
- Unit tests for PathTextizer (7 tests, all passing)
- Test structure for SchemaManager
- Integration test for AssemblyJob
- Test script at `script/test_graph_assembly.rb`

## How It Works

### Pipeline Flow
1. **Schema Setup** - Creates constraints and indexes in Neo4j
2. **Node Loading** - Loads all entities from ActiveRecord to Neo4j
3. **Edge Loading** - Creates relationships based on verb glossary
4. **Deduplication** - Merges duplicate nodes intelligently
5. **Orphan Removal** - Cleans up disconnected nodes
6. **Integrity Check** - Verifies graph meets all requirements

### Key Features
- **Rights-First Design** - Every content node has a rights pointer
- **Verb Glossary Compliance** - All relationships use approved verbs
- **Automatic Reverse Edges** - Creates bidirectional relationships
- **Path Textization** - Converts graph paths to readable sentences
- **Comprehensive Statistics** - Tracks all operations for monitoring

## Testing the Implementation

### Prerequisites
1. Neo4j must be running (use Docker Compose):
```bash
docker-compose up neo4j
```

2. Ensure previous stages have completed data:
```bash
# Check for data from Stage 4
rails c
IngestBatch.where(status: 'pool_filling_completed').count
```

### Running Graph Assembly

#### Option 1: Test Script (Recommended)
```bash
rails runner script/test_graph_assembly.rb
```
This script:
- Creates test data if needed
- Runs the graph assembly
- Displays statistics
- Tests path textization

#### Option 2: Manual Execution
```ruby
# In Rails console
batch = IngestBatch.where(status: 'pool_filling_completed').first
Graph::AssemblyJob.perform_now(batch.id)

# Check results
batch.reload
puts batch.graph_assembly_stats
```

#### Option 3: Run Tests
```bash
# Run path textizer tests
rails test test/services/graph/path_textizer_test.rb

# Run all graph-related tests
rails test test/services/graph/
```

### Verifying in Neo4j

Connect to Neo4j Browser (http://localhost:7474) and run:

```cypher
// Count all nodes
MATCH (n) RETURN labels(n)[0] as Label, count(n) as Count

// Count all relationships
MATCH ()-[r]->() RETURN type(r) as Type, count(r) as Count

// View a sample path
MATCH path = (i:Idea)-[:EMBODIES]->(m:Manifest)-[:ELICITS]->(e:Experience)
RETURN path LIMIT 1

// Check rights connections
MATCH (n)-[:HAS_RIGHTS]->(r:ProvenanceAndRights)
RETURN labels(n)[0] as NodeType, count(n) as Count
```

## Statistics Tracked

The graph assembly process tracks:
- `nodes_created` - Total nodes created
- `edges_created` - Total edges created
- `nodes_by_pool` - Breakdown by pool type
- `edges_by_verb` - Breakdown by relationship type
- `reverse_edges_created` - Count of reverse relationships
- `duplicates_resolved` - Nodes merged
- `orphans_removed` - Disconnected nodes removed
- `constraints_created` - Schema constraints added
- `indexes_created` - Performance indexes added
- `integrity_check` - Summary of validation results

## Next Steps

With Stage 5 complete, the knowledge graph is now assembled and ready for:
- **Stage 6**: Representation & Retrieval Indices (pgvector embeddings)
- **Stage 7**: Literacy Scoring & Gaps
- **Stage 8**: Autogenerated Deliverables

The graph can now be queried for:
- Path finding between concepts
- Relationship traversal
- Pattern matching
- Provenance tracking
- Rights-aware filtering

## Troubleshooting

### Neo4j Connection Issues
```bash
# Check if Neo4j is running
docker-compose ps

# Check Neo4j logs
docker-compose logs neo4j

# Restart Neo4j
docker-compose restart neo4j
```

### Missing Data Issues
```bash
# Ensure previous stages completed
rails runner "puts IngestBatch.pluck(:id, :status)"

# Run previous stages if needed
rails runner script/test_lexicon_bootstrap.rb
# Then run pool extraction...
```

### Graph Assembly Failures
Check the error in batch stats:
```ruby
batch = IngestBatch.find(id)
puts batch.graph_assembly_stats['error']
```

## Architecture Notes

The implementation follows these principles:
1. **Idempotent Operations** - Can be run multiple times safely (MERGE vs CREATE)
2. **Transaction Safety** - All operations in a single transaction
3. **Graceful Degradation** - Handles missing optional pools
4. **Comprehensive Logging** - Every operation is logged
5. **Statistics Tracking** - Full visibility into what was done

The graph assembly stage is now complete and ready for use!