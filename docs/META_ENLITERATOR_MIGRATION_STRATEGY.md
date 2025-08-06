# Meta-Enliterator Migration Strategy

## Executive Summary

We have successfully implemented database-per-EKN isolation architecture. The existing pipeline data from processing the Enliterator codebase (Batch #7) exists in the default Neo4j database mixed with Burning Man data. Since the nodes don't have batch_id properties, we cannot easily separate the datasets for migration.

## Current Situation

### What We Have

1. **Completed Pipeline Data (Batch #7)**
   - 224 IngestItems processed from Enliterator codebase
   - Literacy Score: 75.0
   - Status: completed
   - Data Location: Default Neo4j database (mixed with BM data)

2. **Database Isolation Architecture** ✅
   - Neo4j Desktop with multi-database support
   - Database-per-EKN implementation complete
   - PostgreSQL schema-per-EKN ready
   - File storage isolation ready

3. **Neo4j Default Database Contents**
   - Contains BOTH Enliterator and Burning Man nodes
   - No batch_id properties on nodes (can't filter by batch)
   - No timestamps on nodes (can't filter by date)
   - ~280k total nodes (mixed datasets)

## The Challenge

The original pipeline (Stages 0-8) was built before the isolation architecture. It wrote all data to:
- Default Neo4j database (`neo4j`)
- Default PostgreSQL tables
- Shared file storage

The nodes in Neo4j don't have batch_id properties, making it impossible to cleanly extract just the Enliterator-specific nodes.

## Recommended Solution: Fresh Pipeline Run

### Why Fresh is Better

1. **Clean Separation** - No risk of data contamination
2. **Proper Isolation** - Data goes directly to isolated database
3. **Pipeline Updates** - Use the improved pipeline with isolation
4. **Integrity** - Ensures all relationships are preserved
5. **Testing** - Validates the full isolated pipeline

### Implementation Steps

#### Step 1: Update Pipeline Stages for Isolation

Update Stage 5 (Graph Assembly) to use isolated databases:

```ruby
# app/jobs/pipeline/graph_assembly_job.rb
def perform(ingest_batch_id)
  batch = IngestBatch.find(ingest_batch_id)
  
  # Ensure isolated database exists
  batch.ensure_neo4j_database_exists!
  
  # Use isolated database for graph operations
  graph_service = Graph::QueryService.new(batch)
  # ... rest of graph assembly
end
```

#### Step 2: Create Meta-Enliterator EKN

```bash
rails runner script/create_meta_enliterator_ekn.rb
```

This creates:
- Neo4j database: `ekn-{id}`
- PostgreSQL schema: `ekn_{id}`
- File storage: `/storage/ekns/{id}/`

#### Step 3: Prepare Enliterator Bundle

```bash
# Create a fresh zip of the codebase
cd /path/to/enliterator
zip -r enliterator_codebase.zip . \
  -x "*.git*" \
  -x "*node_modules*" \
  -x "*tmp/*" \
  -x "*storage/*" \
  -x "*log/*"
```

#### Step 4: Run Pipeline with Isolation

```ruby
# Start the pipeline with the isolated EKN
ekn = IngestBatch.find_by(name: "Meta-Enliterator")
ekn.update!(source_type: 'zip_bundle', status: 'pending')

# Process the bundle
Pipeline::IntakeJob.perform_later(ekn.id, '/path/to/enliterator_codebase.zip')
```

#### Step 5: Verify Isolation

```bash
# Check isolated database
rails runner "
  ekn = IngestBatch.find_by(name: 'Meta-Enliterator')
  service = Graph::QueryService.new(ekn)
  stats = service.get_statistics
  puts stats
"
```

## Alternative: Keep Mixed Data

If we decide not to re-run the pipeline:

### Option A: Use Default Database
- Keep using the mixed data in default database
- Accept that Enliterator and BM data are mixed
- Simple but not ideal for production

### Option B: Manual Filtering
- Try to identify Enliterator nodes by name patterns
- Risk: May miss nodes or include wrong ones
- Not recommended

### Option C: Export Everything
- Copy ALL nodes to isolated database
- Includes both datasets
- Later manually clean up BM data

## Pipeline Updates Required

To support database-per-EKN, these stages need updates:

### Stage 3: Lexicon Bootstrap
```ruby
# Store in isolated PostgreSQL schema
ApplicationRecord.connection.execute(<<-SQL)
  INSERT INTO #{batch.postgres_schema_name}.lexicon_entries ...
SQL
```

### Stage 4: Pool Filling
```ruby
# Store in isolated PostgreSQL schema
ApplicationRecord.connection.execute(<<-SQL)
  INSERT INTO #{batch.postgres_schema_name}.entities ...
SQL
```

### Stage 5: Graph Assembly
```ruby
# Use isolated Neo4j database
graph_service = Graph::QueryService.new(batch)
# All operations go to batch.neo4j_database_name
```

### Stage 6: Embeddings
```ruby
# Store in isolated PostgreSQL schema
ApplicationRecord.connection.execute(<<-SQL)
  INSERT INTO #{batch.postgres_schema_name}.embeddings ...
SQL
```

## Benefits of This Approach

1. **True Isolation** - Each EKN completely separated
2. **Clean Data** - No contamination between domains
3. **Scalable** - Can handle thousands of EKNs
4. **Secure** - Medical data never touches festival data
5. **Maintainable** - Clear boundaries for each knowledge domain

## Timeline

1. **Today**: Update pipeline stages (2-3 hours)
2. **Tomorrow**: Run fresh pipeline with Meta-Enliterator (1 hour)
3. **Day 3**: Verify Navigator works with isolated data (1 hour)
4. **Day 4**: Create admin UI for EKN management (4 hours)

## Conclusion

While we have the completed pipeline data in the default database, the cleanest path forward is to:

1. Update the pipeline to use database-per-EKN
2. Create a fresh Meta-Enliterator EKN
3. Run the pipeline again with proper isolation

This ensures our first production EKN demonstrates the full power of the isolation architecture and sets the pattern for all future Knowledge Navigators.

The mixed data in the default database can remain as a reference/development dataset, while production EKNs use complete isolation.