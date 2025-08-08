# Neo4j Setup and Configuration for Enliterator

## CRITICAL: Read This First

**Neo4j Desktop is running (NOT Homebrew, NOT Docker)**
- **URL**: bolt://100.104.170.10:8687 (Tailscale address, port 8687)
- **Authentication**: DISABLED (uses Neo4j::Driver::AuthTokens.none)
- **Multi-database Support**: FULLY ENABLED
- **Database Naming**: Each EKN gets `ekn-{id}` database
- **Configuration**: `/config/initializers/neo4j.rb` has the ONLY correct settings

## DO NOT:
- ❌ Look for Docker containers or Homebrew services
- ❌ Try to start a new Neo4j instance
- ❌ Change the configuration anywhere except neo4j.rb
- ❌ Override the URL or authentication settings

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
1. Is Neo4j Desktop running? Check the Neo4j Desktop application
2. Can you connect directly? `rails runner 'puts Graph::Connection.instance.driver.verify_connectivity'`
3. Check the connection URL matches: bolt://100.104.170.10:8687

### Issue 3: Authentication Issues
**Authentication is DISABLED in Neo4j Desktop:**
- The driver uses `Neo4j::Driver::AuthTokens.none`
- No username or password required
- Configuration in `/config/initializers/neo4j.rb`

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

### Environment Variables
The configuration in `/config/initializers/neo4j.rb` uses these with defaults:
```bash
NEO4J_URL=bolt://100.104.170.10:8687  # Default in neo4j.rb
NEO4J_USERNAME=""  # Not used - auth disabled
NEO4J_PASSWORD=""  # Not used - auth disabled
```

## Neo4j Browser Access

Access Neo4j Browser through Neo4j Desktop application
- No authentication required (auth disabled)
- Multiple databases visible and manageable

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