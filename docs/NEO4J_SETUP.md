# Neo4j Setup and Configuration for Enliterator

## CRITICAL: Read This First

**Neo4j is running LOCALLY via Homebrew, NOT Docker**
- **URL**: bolt://127.0.0.1:7687 (or bolt://localhost:7687)
- **Username**: neo4j
- **Password**: cheese28
- **Current Data**: 280,739 nodes (as of 2025-08-06)
- **Installation**: Homebrew (`brew services list` shows neo4j)

## DO NOT:
- ❌ Look for Docker containers
- ❌ Try to start a new Neo4j instance
- ❌ Assume the graph is empty if queries return no results
- ❌ Change the password from cheese28

## Common Issues and Solutions

### Issue 1: Queries Return Empty Results
**Symptom**: Graph::QueryService returns empty arrays despite Neo4j having data

**Cause**: The batch_id filter doesn't match the data in Neo4j

**Solution**: 
```ruby
# Option 1: Query without batch_id filter
service = Graph::QueryService.new(nil)  # Pass nil, not a batch_id

# Option 2: Check what batch_ids exist in Neo4j
result = driver.session.run("MATCH (n) RETURN DISTINCT n.batch_id LIMIT 10")
```

### Issue 2: "Neo4j not connected" Errors
**Check these in order:**
1. Is Neo4j running? `brew services list | grep neo4j`
2. Can you connect directly? `rails runner 'puts Graph::Connection.instance.driver.verify_connectivity'`
3. Check the logs: `tail -f /opt/homebrew/var/log/neo4j/neo4j.log`

### Issue 3: Authentication Failures
**The correct credentials are:**
- Username: `neo4j`
- Password: `cheese28`
- These are hardcoded in `/config/initializers/neo4j.rb`

## Verifying Neo4j Health

Run this script to verify everything is working:

```bash
rails runner 'scripts/check_neo4j_health.rb'
```

## What's Actually in the Graph?

The Neo4j database contains the FULL Enliterator codebase graph:
- **Nodes**: Code entities (files, classes, methods, etc.)
- **Relationships**: Dependencies, calls, inheritance, etc.
- **Source**: Generated from analyzing the Enliterator codebase itself

**Important**: The nodes do NOT have reliable batch_id properties. This is why filtering by batch_id often fails.

## Configuration Files

### /config/initializers/neo4j.rb
- Defines the connection settings
- Creates the Graph::Connection singleton
- Uses environment variables with fallbacks

### Environment Variables (Optional)
```bash
NEO4J_URL=bolt://127.0.0.1:7687
NEO4J_USERNAME=neo4j
NEO4J_PASSWORD=cheese28
```

## Neo4j Browser Access

Access the Neo4j Browser at: http://localhost:7474
- Username: neo4j
- Password: cheese28

## Sample Queries That Work

```cypher
// Count all nodes
MATCH (n) RETURN count(n);

// See node types
MATCH (n) RETURN DISTINCT labels(n), count(n);

// Find nodes by name
MATCH (n) WHERE n.name CONTAINS 'Enliterator' RETURN n LIMIT 10;

// See relationships
MATCH (n)-[r]->(m) RETURN DISTINCT type(r), count(r) LIMIT 10;
```

## For Debugging

When Graph::QueryService returns empty results:

1. First, verify Neo4j has data:
```ruby
driver = Graph::Connection.instance.driver
session = driver.session
result = session.run("MATCH (n) RETURN count(n) as count")
puts "Total nodes: #{result.single['count']}"
session.close
```

2. Check if batch_id filtering is the issue:
```ruby
# This will likely return 0
service = Graph::QueryService.new(some_batch_id)
service.search_entities("test")  # Returns []

# This should work
service = Graph::QueryService.new(nil)  # No batch filter
service.search_entities("test")  # Should return results
```

## The Truth About Batch IDs

The nodes in Neo4j were NOT created with batch_id properties from the Enliterator pipeline. They were likely imported directly or created through a different process. This is why:
- Filtering by batch_id returns empty results
- We need to either:
  1. Not filter by batch_id for the Knowledge Navigator
  2. Add batch_id properties to existing nodes
  3. Use a different filtering mechanism

---

**Remember**: The graph is FULL of data. If queries return empty, it's a filtering problem, not a data problem.