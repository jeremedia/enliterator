# Stage 5: Graph Assembly - Detailed Documentation

## Overview
Stage 5 (Graph Assembly) loads extracted entities and relationships into Neo4j, creating the knowledge graph that powers the EKN. This stage has critical transaction management requirements and uses EKN-specific databases for isolation.

## Job Implementation
**File**: `/app/jobs/graph/assembly_job.rb`
**Queue**: `:pipeline`
**Base Class**: `Pipeline::BaseJob`

## CRITICAL BUG: Transaction Separation

### The Problem
Neo4j does not allow schema modifications (constraints, indexes) and data operations in the same transaction:

```ruby
# THIS FAILS
driver.session do |session|
  session.write_transaction do |tx|
    # Schema modification
    tx.run("CREATE CONSTRAINT FOR (n:Idea) REQUIRE n.id IS NOT NULL")
    
    # Data operation in same transaction - FAILS!
    tx.run("CREATE (n:Idea {id: 1})")  
    # Error: "Tried to execute Write query after executing Schema modification"
  end
end
```

### The Solution
Schema and data operations MUST be in separate transactions:

```ruby
# THIS WORKS
driver.session do |session|
  # Transaction 1: Schema only
  session.write_transaction do |tx|
    Graph::SchemaManager.new(tx).ensure_constraints!
  end
  
  # Transaction 2: Data only
  session.write_transaction do |tx|
    Graph::NodeLoader.new(tx, @batch).load_all
    Graph::EdgeLoader.new(tx, @batch).load_all
  end
end
```

## Input Requirements

### Database Requirements
- EKN must have a dedicated Neo4j database
- Database name format: `ekn-{id}` (e.g., `ekn-37`)
- Database created if not exists

### Entity Requirements
From Stage 4, must have:
- Pool entities (Idea, Manifest, Experience, etc.)
- Each entity must have ProvenanceAndRights
- Entities must have required fields per pool type

## Processing Logic

### Main Flow
```ruby
def perform(pipeline_run_id)
  log_progress "Starting graph assembly for EKN: #{@ekn.name}"
  
  # Step 1: Ensure database exists
  ensure_ekn_database!
  
  # Step 2: Setup schema (separate transaction)
  setup_graph_schema
  
  # Step 3: Load data (separate transaction)
  load_graph_data
  
  # Step 4: Update item statuses
  mark_items_complete
end
```

### Database Management
```ruby
def ensure_ekn_database!
  database_name = @ekn.neo4j_database_name  # e.g., "ekn-37"
  
  Graph::DatabaseManager.new(@ekn).ensure_database!
  # Creates database if not exists
  # Sets as current database for EKN
  
  log_progress "Using Neo4j database: #{database_name}"
end
```

### Schema Setup (Transaction 1)
```ruby
def setup_graph_schema
  Graph::Connection.with_database(@ekn.neo4j_database_name) do |driver|
    driver.session do |session|
      session.write_transaction do |tx|
        manager = Graph::SchemaManager.new(tx)
        
        # Create constraints for each pool
        manager.create_constraint_for_pool('Idea')
        manager.create_constraint_for_pool('Manifest')
        manager.create_constraint_for_pool('Experience')
        # ... etc for all Ten Pool Canon
        
        # Create required field constraints
        manager.ensure_required_fields!
      end
    end
  end
end
```

### Data Loading (Transaction 2)
```ruby
def load_graph_data
  Graph::Connection.with_database(@ekn.neo4j_database_name) do |driver|
    driver.session do |session|
      session.write_transaction do |tx|
        # Load nodes
        node_results = Graph::NodeLoader.new(tx, @batch).load_all
        track_metric :nodes_created, node_results[:total_nodes]
        
        # Load edges
        edge_results = Graph::EdgeLoader.new(tx, @batch).load_all
        track_metric :edges_created, edge_results[:total_edges]
        
        # Resolve duplicates
        dedup_results = Graph::Deduplicator.new(tx).resolve_duplicates
        track_metric :duplicates_resolved, dedup_results[:merged]
      end
    end
  end
end
```

## Node Loading Details

### NodeLoader Implementation
```ruby
class Graph::NodeLoader
  def load_all
    load_ideas
    load_manifests
    load_experiences
    # ... other pools
  end
  
  def load_ideas
    Idea.joins(:provenance_and_rights).find_each do |idea|
      properties = build_idea_properties(idea)
      create_node('Idea', properties)
    end
  end
  
  def build_idea_properties(idea)
    {
      id: idea.id,
      label: idea.label,
      abstract: idea.abstract,
      principle_tags: sanitize_for_neo4j(idea.principle_tags),
      valid_time_start: idea.valid_time_start.to_s,
      repr_text: idea.repr_text,
      rights_id: idea.provenance_and_rights_id
    }
  end
  
  def create_node(label, properties)
    query = "MERGE (n:#{label} {id: $id}) SET n += $properties"
    @tx.run(query, id: properties[:id], properties: properties)
  end
end
```

### CRITICAL: Data Sanitization for Neo4j

Neo4j only accepts primitive types or arrays of primitives. Complex types must be serialized:

```ruby
def sanitize_for_neo4j(value)
  case value
  when Array
    # Arrays with hashes/nested arrays must be JSON
    if value.any? { |v| v.is_a?(Hash) || v.is_a?(Array) }
      value.to_json  # Convert to JSON string
    else
      value  # Array of primitives is OK
    end
  when Hash
    value.to_json  # Hashes must be JSON strings
  when nil
    nil
  else
    value  # Primitives are OK
  end
end
```

### Common Sanitization Issues
```ruby
# WRONG - Neo4j will reject these
properties = {
  metadata: { key: 'value' },        # Hash not allowed
  tags: [{ name: 'tag1' }],          # Array of hashes not allowed
  polymorphic_ref: experience_object  # ActiveRecord object not allowed
}

# CORRECT - Neo4j will accept these
properties = {
  metadata: '{"key":"value"}',       # JSON string OK
  tags: '["tag1","tag2"]',           # JSON string OK
  polymorphic_ref_id: experience.id, # Split into primitives
  polymorphic_ref_type: 'Experience'
}
```

## Edge Loading Details

### EdgeLoader Implementation
```ruby
class Graph::EdgeLoader
  def load_all
    load_relational_edges
    load_evolutionary_edges
    load_emanation_edges
  end
  
  def load_relational_edges
    Relational.find_each do |relational|
      create_edge(
        source_label: relational.source_type,
        source_id: relational.source_id,
        target_label: relational.target_type,
        target_id: relational.target_id,
        relation_type: relational.relation_type,
        properties: {
          strength: relational.strength,
          valid_time_start: relational.valid_time_start.to_s
        }
      )
    end
  end
  
  def create_edge(params)
    query = <<~CYPHER
      MATCH (source:#{params[:source_label]} {id: $source_id})
      MATCH (target:#{params[:target_label]} {id: $target_id})
      MERGE (source)-[r:#{params[:relation_type]}]->(target)
      SET r += $properties
    CYPHER
    
    @tx.run(query, 
      source_id: params[:source_id],
      target_id: params[:target_id],
      properties: params[:properties]
    )
  end
end
```

## Schema Constraints

### Required Constraints
```cypher
# ID constraints (unique and required)
CREATE CONSTRAINT FOR (n:Idea) REQUIRE n.id IS NOT NULL
CREATE CONSTRAINT FOR (n:Manifest) REQUIRE n.id IS NOT NULL
CREATE CONSTRAINT FOR (n:Experience) REQUIRE n.id IS NOT NULL

# Canonical description (required for Lexicon)
CREATE CONSTRAINT FOR (n:Lexicon) REQUIRE n.canonical_description IS NOT NULL

# Rights reference
CREATE CONSTRAINT FOR (n:ProvenanceAndRights) REQUIRE n.id IS NOT NULL
```

### Backfilling Required Fields
Before creating constraints, existing nodes must have required fields:

```ruby
def backfill_canonical_description
  query = <<~CYPHER
    MATCH (n:Lexicon)
    WHERE n.canonical_description IS NULL AND n.definition IS NOT NULL
    SET n.canonical_description = n.definition
    RETURN count(n) as updated_count
  CYPHER
  
  result = @tx.run(query)
  log_progress "Backfilled #{result.first[:updated_count]} Lexicon nodes"
end
```

## Output Data

### Neo4j Graph Structure
```
Nodes:
- Idea nodes with properties
- Manifest nodes with properties
- Experience nodes with properties
- Lexicon nodes with canonical terms
- ProvenanceAndRights nodes

Edges:
- EMBODIES (Idea -> Manifest)
- ELICITS (Manifest -> Experience)
- RELATES_TO (generic relations)
- EVOLVES_FROM (evolutionary links)
```

### IngestItem Updates
```ruby
{
  graph_status: 'assembled',
  embedding_status: 'pending',  # Ready for Stage 6
  graph_metadata: {
    nodes_created: 45,
    edges_created: 67,
    assembled_at: '2025-08-07 12:00:00'
  }
}
```

## Metrics Tracked

```ruby
{
  nodes_created: 45,        # Total nodes loaded
  edges_created: 67,        # Total relationships
  duplicates_resolved: 3,   # Merged duplicate nodes
  duration: 28.5           # Seconds
}
```

## Common Issues and Solutions

### Issue 1: Schema/Data Transaction Error
**Symptom**: "Tried to execute Write query after executing Schema modification"
**Cause**: Schema and data operations in same transaction
**Solution**: Use separate transactions (see solution at top)

### Issue 2: Map{} Property Error
**Symptom**: "Property values can only be of primitive types or arrays thereof"
**Cause**: Passing hashes, AR objects, or nested arrays to Neo4j
**Solution**: Sanitize all data before passing to Neo4j

### Issue 3: Missing canonical_description
**Symptom**: "ConstraintValidationFailed: Node with label `Lexicon` must have property `canonical_description`"
**Cause**: Existing nodes don't have required field
**Solution**: Backfill before creating constraint

### Issue 4: Connection Pool Exhaustion
**Symptom**: Timeout waiting for Neo4j connection
**Cause**: Not properly closing sessions
**Solution**: Always use block form with proper cleanup

## Performance Characteristics

### Timing
- Database creation: ~1 second (first time only)
- Schema setup: ~2 seconds
- Node loading: ~10ms per node
- Edge loading: ~15ms per edge
- Deduplication: ~500ms

### Typical Performance (100 entities)
- 100 nodes: ~1 second
- 200 edges: ~3 seconds
- Total: ~5-10 seconds

### Optimization Opportunities
1. Batch node creation with UNWIND
2. Parallel edge creation
3. Index commonly queried properties
4. Connection pooling

## Testing Recommendations

### Unit Tests
```ruby
# Test sanitization
assert_equal '{"key":"value"}', sanitize_for_neo4j({key: 'value'})
assert_equal ['a','b'], sanitize_for_neo4j(['a','b'])
assert_equal '["a",{"b":"c"}]', sanitize_for_neo4j(['a', {b: 'c'}])

# Test constraint creation
mock_tx = double('transaction')
expect(mock_tx).to receive(:run).with(/CREATE CONSTRAINT/)
SchemaManager.new(mock_tx).ensure_constraints!
```

### Integration Tests
```ruby
# Test full graph assembly
VCR.use_cassette('neo4j_graph_assembly') do
  GraphAssemblyJob.perform_now(pipeline_run.id)
  
  # Verify in Neo4j
  result = neo4j_query("MATCH (n) RETURN count(n) as count")
  assert_equal 45, result.first[:count]
end
```

## Debugging Neo4j

### Check Database
```cypher
# Show current database
SHOW DATABASE ekn-37

# Count nodes by label
MATCH (n) RETURN labels(n)[0] as Label, count(n) as Count

# Check constraints
SHOW CONSTRAINTS

# Find nodes without required fields
MATCH (n:Lexicon) 
WHERE n.canonical_description IS NULL 
RETURN n LIMIT 10
```

### Monitor Transactions
```ruby
# In Rails console
Graph::Connection.with_database('ekn-37') do |driver|
  driver.session do |session|
    result = session.run("MATCH (n) RETURN count(n)")
    puts result.single[:count]
  end
end
```

## Next Stage
Items with `graph_status: 'assembled'` proceed to Stage 6 (Embeddings) for vector representation generation.