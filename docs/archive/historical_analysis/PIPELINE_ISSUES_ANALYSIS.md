# Pipeline Issues Analysis

## Critical Understanding
**Goal**: Create ONE Meta-Enliterator by processing Enliterator codebase
**Current State**: 21 failed EKN attempts cluttering the system
**Required**: Fix bugs, clean slate, ONE successful pipeline run

## Identified Bugs

### 1. IngestItem Attribute Error
**Error**: `unknown attribute 'error_message' for IngestItem`
**Cause**: Code using `error_message` but field is actually `triage_error`
**Fix**: Update all references to use `triage_error`

### 2. Neo4j Transaction Error  
**Error**: `Tried to execute Write query after executing Schema modification`
**Cause**: Schema operations and data operations in same transaction
**Status**: Already fixed in Graph::AssemblyJob but still occurring
**Fix**: Verify fix is complete and working

### 3. Missing EKN Database
**Error**: `Database does not exist. Database name: 'ekn-21'`
**Cause**: EKN database not created before use
**Fix**: Ensure Graph::DatabaseManager.ensure_database_exists is called

### 4. Poor Extraction Quality
**Symptom**: 216 files → only 3 entities created
**Issues**:
- All 216 items failed rights processing
- Likely due to missing fields or validation errors
**Fix**: Debug extraction and rights assignment logic

## The Clean Slate Approach

### Phase 1: Fix Bugs
1. Fix IngestItem attribute name
2. Verify Neo4j transaction separation
3. Ensure database creation
4. Debug extraction failures

### Phase 2: Clean Database
```ruby
# Destroy all failed attempts
Ekn.destroy_all
IngestBatch.destroy_all
EknPipelineRun.destroy_all
IngestItem.destroy_all
# Clear all entity tables
Idea.destroy_all
Manifest.destroy_all
# etc...
```

### Phase 3: Create Meta-Enliterator Bundle
```ruby
# Create bundle of Enliterator codebase
MetaEnliteration::BundleCreator.new.call
```

### Phase 4: Run ONE Pipeline
```ruby
# Create the Meta-EKN
ekn = Ekn.create!(
  name: "Meta-Enliterator",
  domain_type: "technical",
  personality: "helpful_guide"
)

# Process bundle through pipeline
Pipeline::Orchestrator.new(ekn).process_bundle(bundle_path)
```

### Phase 5: Verify Success
- Pipeline completes all 9 stages
- Literacy score > 70
- Graph has meaningful nodes and relationships
- Can answer questions about Enliterator

## Success Criteria
✅ ONE EKN in database (the Meta-Enliterator)
✅ Complete pipeline run without manual intervention
✅ Meaningful knowledge graph created
✅ Can converse about Enliterator concepts

## Philosophy
Each attempt should be atomic:
- Either succeed completely → Meta-EKN exists
- Or fail and teach us → clean slate and try again

No partial successes. No frankenstein assemblies.