# GitHub Issue #51: Implement Database-per-EKN in Pipeline & Create Meta-Enliterator Navigator

## 🎯 Problem Statement

We've successfully built database-per-EKN isolation architecture, but the pipeline stages (0-8) still write to shared resources. The existing Meta-Enliterator data (from processing the Enliterator codebase) is mixed with Burning Man data in the default Neo4j database with no way to cleanly separate them.

**Critical Issues:**
- Pipeline writes to default Neo4j database for ALL EKNs
- PostgreSQL data goes to shared tables, not isolated schemas
- No data isolation between knowledge domains (medical data would mix with festival data)
- Existing Meta-Enliterator data is contaminated with unrelated datasets

## 🚀 Solution

Update all pipeline stages to use the database-per-EKN isolation architecture, then run a fresh pipeline to create a clean Meta-Enliterator Knowledge Navigator.

## 📋 Implementation Tasks

### Phase 1: Update Pipeline for Isolation (Priority: CRITICAL)

#### Task 1: Update Stage 3 - Lexicon Bootstrap
- [ ] Modify `Lexicon::BootstrapJob` to use `batch.postgres_schema_name`
- [ ] Update `LexiconEntry` model to write to isolated schema
- [ ] Update `Graph::LexiconWriter` to use `batch.neo4j_database_name`
- [ ] Add tests for schema isolation

#### Task 2: Update Stage 4 - Pool Filling  
- [ ] Modify `Pools::ExtractionJob` to use isolated PostgreSQL schema
- [ ] Update all Pool models to write to `batch.postgres_schema_name`
- [ ] Ensure pool entities are stored in correct schema
- [ ] Add validation for schema isolation

#### Task 3: Update Stage 5 - Graph Assembly
- [ ] Modify `Pipeline::GraphAssemblyJob` to use `Graph::QueryService.new(batch)`
- [ ] Update `Graph::NodeWriter` to use isolated Neo4j database
- [ ] Update `Graph::RelationshipWriter` for isolated database
- [ ] Ensure all graph operations use `batch.neo4j_database_name`
- [ ] Add comprehensive isolation tests

#### Task 4: Update Stage 6 - Embeddings
- [ ] Use Neo4j GenAI within each EKN database
- [ ] Remove pgvector model/table usage (fully deprecated)
- [ ] Ensure Neo4j vector index creation per EKN database
- [ ] Update semantic search to query Neo4j via `Neo4j::EmbeddingService`

#### Task 5: Update Stage 7 - Literacy Scoring
- [ ] Ensure scoring reads from isolated database
- [ ] Update gap analysis to use isolated resources
- [ ] Store scores in isolated schema

#### Task 6: Update Stage 8 - Deliverables
- [ ] Ensure exports read from isolated database
- [ ] Update all export formats to be EKN-aware
- [ ] Store deliverables in isolated file storage

### Phase 2: Create Meta-Enliterator EKN (Priority: HIGH)

#### Task 7: Prepare Enliterator Bundle
- [ ] Create clean ZIP of Enliterator codebase
- [ ] Exclude unnecessary files (.git, node_modules, tmp, logs)
- [ ] Include all source code, docs, and configuration
- [ ] Verify bundle integrity

#### Task 8: Create and Configure EKN
- [ ] Run `EknManager.create_ekn(name: "Meta-Enliterator")`
- [ ] Verify isolated resources created:
  - [ ] Neo4j database: `ekn-{id}`
  - [ ] PostgreSQL schema: `ekn_{id}`
  - [ ] File storage: `/storage/ekns/{id}/`
- [ ] Configure Navigator to use this EKN

#### Task 9: Run Pipeline with Isolation
- [ ] Start intake with isolated EKN
- [ ] Monitor each stage for proper isolation:
  - [ ] Stage 1: Intake → isolated file storage
  - [ ] Stage 2: Rights → isolated schema
  - [ ] Stage 3: Lexicon → isolated schema + Neo4j
  - [ ] Stage 4: Pools → isolated schema
  - [ ] Stage 5: Graph → isolated Neo4j database
  - [ ] Stage 6: Embeddings → isolated schema
  - [ ] Stage 7: Scoring → isolated resources
  - [ ] Stage 8: Deliverables → isolated storage
- [ ] Verify literacy score ≥ 70

### Phase 3: Validate Knowledge Navigator (Priority: HIGH)

#### Task 10: Test Isolated Navigator
- [ ] Configure NavigatorController to use Meta-Enliterator EKN
- [ ] Test conversational interface with isolated data
- [ ] Verify no data leakage from other EKNs
- [ ] Test queries about Enliterator architecture
- [ ] Verify visualizations work with isolated data

#### Task 11: Documentation
- [ ] Document pipeline isolation changes
- [ ] Create migration guide for existing data
- [ ] Update CLAUDE.md with isolation patterns
- [ ] Add examples of multi-EKN usage

## 🎨 Technical Design

### Database Isolation Pattern

```ruby
# Before (shared resources)
class Pipeline::GraphAssemblyJob
  def perform(batch_id)
    session = @driver.session # Uses default database
    # All EKNs write to same database!
  end
end

# After (isolated resources)
class Pipeline::GraphAssemblyJob
  def perform(batch_id)
    batch = IngestBatch.find(batch_id)
    batch.ensure_neo4j_database_exists!
    
    service = Graph::QueryService.new(batch)
    # Automatically uses batch.neo4j_database_name
  end
end
```

### Schema Isolation Pattern

```ruby
# Before (shared tables)
embedding = Embedding.create!(entity_id: 123, ...)

# After (isolated schema)
ApplicationRecord.connection.execute(<<-SQL)
  INSERT INTO #{batch.postgres_schema_name}.embeddings
  (entity_id, embedding, metadata)
  VALUES ($1, $2, $3)
SQL, [123, vector, metadata.to_json])
```

## 📊 Success Criteria

1. **Complete Isolation**: Each EKN's data is completely isolated
2. **No Cross-Contamination**: Medical data never touches festival data
3. **Clean Meta-Enliterator**: Fresh pipeline run with zero BM data
4. **Working Navigator**: Conversational interface works with isolated data
5. **Performance**: No degradation from isolation architecture
6. **Scalability**: Can handle 100+ EKNs simultaneously

## 🔍 Testing Strategy

### Unit Tests
- Test each pipeline stage with mock isolated resources
- Verify correct database/schema selection
- Test failure scenarios

### Integration Tests
- Run mini-pipeline with test EKN
- Verify data goes to correct locations
- Test cleanup after deletion

### Isolation Tests
- Create multiple EKNs simultaneously
- Verify zero data leakage
- Test concurrent pipeline runs

## 📈 Impact

### Benefits
- **True Multi-Tenancy**: Each organization gets isolated knowledge domain
- **Security**: Complete data isolation prevents leaks
- **Scalability**: Can serve thousands of EKNs
- **Compliance**: GDPR/HIPAA ready with clean data boundaries
- **Production Ready**: First true production Knowledge Navigator

### Risks
- **Complexity**: More moving parts to manage
- **Migration**: Existing data needs careful handling
- **Performance**: Multiple databases need monitoring

## 🕐 Timeline

### Week 1 (Current)
- Days 1-2: Update pipeline stages (Tasks 1-6)
- Day 3: Test isolation with test EKNs
- Days 4-5: Create Meta-Enliterator bundle and EKN

### Week 2
- Days 1-2: Run fresh pipeline with Meta-Enliterator
- Day 3: Configure and test Navigator
- Days 4-5: Documentation and cleanup

## 📝 Notes

### Why Fresh Pipeline Run?
The existing data has no batch_id markers, making it impossible to cleanly separate Enliterator from Burning Man nodes. A fresh run ensures:
- Clean data from the start
- Proper isolation architecture usage
- True production-ready implementation

### Migration Strategy
The mixed data in the default database remains as reference/development data. All production EKNs use complete isolation.

### Dependencies
- Neo4j Desktop (installed ✅)
- Multi-database support (configured ✅)
- Database-per-EKN architecture (implemented ✅)

## 🏷️ Labels
`pipeline`, `isolation`, `database-per-ekn`, `meta-enliterator`, `production`, `priority:critical`

## 👥 Assignees
@assistant

## 🔗 Related Issues
- #47: OpenAI Integration Overhaul (COMPLETE)
- #50: Stage 9 - Knowledge Navigator Creation (IN PROGRESS)

---

**Created**: 2025-08-06
**Target Completion**: 2025-08-13 (1 week)
**Status**: 🚀 STARTING NOW
