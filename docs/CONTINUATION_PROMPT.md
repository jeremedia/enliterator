# Enliterator Pipeline - Critical Work Continuation

## Executive Summary
The Enliterator pipeline is stuck at Stage 6 (Relationship Discovery) with a fundamentally broken graph - only 18 relationships exist for 1,043 entities (0.02 density when >1.0 is needed). The system cannot progress to stages 7-9 without fixing this. We need methodical, professional engineering to make this production-ready.

## Current Situation

### Pipeline Status (Reality Check)
- **Stages 0-4**: ✅ Working (intake, rights, lexicon, entity extraction)
- **Stage 5**: ⚠️ Nodes loaded to Neo4j, but no relationships
- **Stage 6**: ❌ Relationship Discovery - Creating only 18 of ~1000+ needed relationships
- **Stages 7-9**: ❌ Blocked - Cannot test embeddings, literacy scoring, or deliverables
- **Actual Completion**: ~40% (NOT the claimed 92%)

### Critical Metrics
```
Neo4j Database: ekn-relationship-test-v2
Entities: 1,043 (401 Ideas, 601 Practicals, 41 Experiences)
Relationships: 18 EMBODIES (should be 1000+)
Density: 0.02 relationships/entity (MUST be >1.0)
Last Pipeline: #58 (failed at Stage 6)
```

## What We Just Fixed
1. ✅ Fixed `stage_metadata` → `stage_metrics` typo in RelationshipDiscoveryJob line 380
2. ✅ Fixed `textize_full_path` → `find_and_textize_paths` method call
3. ✅ Implemented EntityClusterer using PostgreSQL (since custom_terms not in Neo4j)
4. ✅ Reduced MIN_CLUSTER_SIZE from 10 to 3 (matching actual data)

## Critical Problems Remaining

### Problem 1: Relationship Creation Failing (HIGHEST PRIORITY)
- **Symptom**: Only 18 of 29 discovered relationships actually created in Neo4j
- **Root Cause**: Entity label matching between PostgreSQL and Neo4j failing
- **Evidence**: Stage 6 discovers 29 relationships but only creates 18
- **File**: `/app/jobs/graph/relationship_discovery_job.rb` line 215-252

### Problem 2: Relationship Discovery Too Limited
- **Symptom**: Only finding 29 relationships for 1,043 entities
- **Root Cause**: Clustering too restrictive, only processing co-occurrence
- **Evidence**: 9 clusters processed, but should find 100s of relationships
- **Files**: 
  - `/app/services/graph/entity_clusterer.rb`
  - `/app/services/pools/relation_extraction_service.rb`

### Problem 3: Graph Essentially Disconnected
- **Symptom**: 0.02 relationships per entity (needs >1.0)
- **Impact**: Makes path finding, navigation, and literacy scoring impossible
- **Solution Needed**: Cross-boundary relationship discovery

## Your Mission

### Phase 1: Debug & Fix Relationship Creation (IMMEDIATE)
```ruby
# Start here - understand why relationships aren't being created
rails runner '
  # Check last pipeline run
  run = EknPipelineRun.find(58)
  batch = run.ingest_batch
  
  # Test relationship creation manually
  # Debug entity label matching
  # Fix create_graph_relationship method
'
```

Key files to examine:
- `/app/jobs/graph/relationship_discovery_job.rb` - Lines 215-252 (create_graph_relationship)
- `/app/services/graph/entity_clusterer.rb` - Lines 54-120 (cluster_by_co_occurrence)

### Phase 2: Expand Relationship Discovery
The system needs to find 1000+ relationships, not 29. Investigate:
1. Why is RelationExtractionService only returning generic verbs like "co_occurs_with"?
2. Why aren't we using the full VERB_GLOSSARY with semantic verbs?
3. Should we be running multiple clustering strategies, not just co_occurrence?

### Phase 3: Achieve Connected Graph (Target: >1.0 density)
Once relationships are being created, we need to:
1. Run full relationship discovery across all entities
2. Implement semantic clustering (not just co-occurrence)
3. Use proper verbs from Graph::EdgeLoader::VERB_GLOSSARY

## Testing Commands

```bash
# Check current graph state
rails runner 'batch = IngestBatch.find(76); ekn = batch.ekn; driver = Graph::Connection.instance.driver; driver.session(database: ekn.neo4j_database_name) { |s| s.read_transaction { |tx| result = tx.run("MATCH (n) RETURN count(n) as nodes UNION ALL MATCH ()-[r]->() WHERE type(r) <> \"HAS_RIGHTS\" RETURN count(r) as relationships").to_a; puts "Nodes: #{result[0]["nodes"]}, Relationships: #{result[1]["relationships"]}" } }'

# Test relationship discovery
rails runner 'run = EknPipelineRun.create!(status: "running", current_stage: "relationships", current_stage_number: 6, stage_statuses: {"relationships" => "running"}, ingest_batch: IngestBatch.find(76)); Graph::RelationshipDiscoveryJob.perform_now(run.id)'

# Check relationship creation errors
rails runner 'SolidQueue::FailedExecution.order(created_at: :desc).first(5).each { |f| puts "#{f.job.class_name}: #{f.error["message"]}" }'
```

## Success Criteria
1. **Immediate**: Fix relationship creation so 29/29 discovered relationships are created
2. **Short-term**: Discover and create 500+ relationships (0.5 density)
3. **Target**: Achieve 1000+ relationships (>1.0 density)
4. **Final**: Complete pipeline run through Stage 9

## Approach Philosophy
- **NO SHORTCUTS**: This needs to work for years in production
- **METHODICAL**: Fix one problem completely before moving to the next
- **TEST EVERYTHING**: Each fix must be verified with actual data
- **DOCUMENT**: Update `/docs/ISSUE_RELATIONSHIP_EXTRACTION_REDESIGN.md` as you go

## Context Files
- Current work tracked in: `/docs/ISSUE_RELATIONSHIP_EXTRACTION_REDESIGN.md`
- Pipeline specification: `/docs/enliterator_enliterated_dataset_literate_runtime_spec_v_1.md`
- Project instructions: `/CLAUDE.md`
- GitHub Issues: https://github.com/jeremedia/enliterator/issues/57

## Start Here
1. Read this entire document
2. Check current graph state with the testing commands above
3. Focus on Problem 1: Why are only 18 of 29 relationships being created?
4. Use `rails console` and `rails runner` to debug interactively
5. Fix systematically - no rushing, no shortcuts

Remember: The goal is not speed but SUCCESS - a production-ready system that successfully processes an EKN's dataset to completion.