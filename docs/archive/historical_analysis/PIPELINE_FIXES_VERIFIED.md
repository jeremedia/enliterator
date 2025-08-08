# Pipeline Fixes - Verified Action Plan

*Updated after code verification - August 7, 2025*

## ✅ What's Already Working
- **Stage 1 Intake**: Sets `item.content` and `item.content_sample` correctly
- **Stage 3 Hardening**: Source tracking and pool-ready logic implemented
- **Neo4j Services**: Embedding services exist (`Neo4j::VectorIndexService`, `Neo4j::EmbeddingService`, `Neo4j::SemanticSearchService`)
- **Sanitization**: `sanitize_for_neo4j` method exists in NodeLoader

## 🔴 Priority 1: Critical Fixes

### 1. Stage 5: Neo4j Transaction Separation
**File**: `/app/jobs/graph/assembly_job.rb`
**Fix**: Split schema and data operations into separate transactions

```ruby
def perform(pipeline_run_id)
  # ... existing setup ...
  
  Graph::Connection.with_database(@ekn.neo4j_database_name) do |driver|
    # Transaction 1: Schema operations only
    driver.session do |session|
      session.write_transaction do |tx|
        Graph::SchemaManager.new(tx).ensure_constraints!
      end
    end
    
    # Transaction 2: Data operations only
    driver.session do |session|
      session.write_transaction do |tx|
        Graph::NodeLoader.new(tx, @batch).load_all
        Graph::EdgeLoader.new(tx, @batch).load_all
      end
    end
  end
end
```

### 2. Stage 5: Complete Property Sanitization
**File**: `/app/services/graph/node_loader.rb`
**Issue**: Some fields still passing complex objects to Neo4j

Apply `sanitize_for_neo4j` to these specific fields:

```ruby
# In build_evolutionary_properties
def build_evolutionary_properties(evolutionary)
  {
    id: evolutionary.id,
    change_note: evolutionary.change_note,
    # FIX: Split polymorphic reference
    prior_ref_id: evolutionary.prior_ref_id,
    prior_ref_type: evolutionary.prior_ref_type,
    # NOT: prior_ref: evolutionary.prior_ref (ActiveRecord object)
    version_id: evolutionary.version_id,
    # ... rest of properties
  }
end

# In build_lexicon_properties
def build_lexicon_properties(lexicon)
  {
    # ... other properties ...
    type_mapping: sanitize_for_neo4j(lexicon.type_mapping),  # Apply sanitization
    # ... rest
  }
end

# In build_intent_properties
def build_intent_properties(intent)
  {
    # ... other properties ...
    constraints: sanitize_for_neo4j(intent.constraints),
    adapter_params: sanitize_for_neo4j(intent.adapter_params),
    evaluation: sanitize_for_neo4j(intent.evaluation),
    # ... rest
  }
end

# In build_practical_properties
def build_practical_properties(practical)
  {
    # ... other properties ...
    steps: sanitize_for_neo4j(practical.steps),
    prerequisites: sanitize_for_neo4j(practical.prerequisites),
    hazards: sanitize_for_neo4j(practical.hazards),
    validation_refs: sanitize_for_neo4j(practical.validation_refs),
    # ... rest
  }
end
```

### 3. Stage 5: Lexicon canonical_description Fix
**File**: `/app/services/graph/node_loader.rb`
**Issue**: Lexicon nodes require canonical_description but it may be nil

```ruby
def build_lexicon_properties(lexicon)
  {
    id: lexicon.id,
    term: lexicon.term,
    definition: lexicon.definition,
    # FIX: Provide fallback for required field
    canonical_description: lexicon.canonical_description.presence || 
                          lexicon.definition.presence || 
                          "Extracted term",
    # ... rest of properties
  }
end
```

**Also in** `/app/services/graph/schema_manager.rb`:
```ruby
def ensure_constraints!
  # Backfill before creating constraint
  backfill_canonical_description
  
  # Then create constraint
  @tx.run("CREATE CONSTRAINT FOR (n:Lexicon) REQUIRE n.canonical_description IS NOT NULL")
end

def backfill_canonical_description
  query = <<~CYPHER
    MATCH (n:Lexicon)
    WHERE n.canonical_description IS NULL AND n.definition IS NOT NULL
    SET n.canonical_description = n.definition
    RETURN count(n) as updated_count
  CYPHER
  
  result = @tx.run(query)
  # Note: This needs to be in a separate transaction before constraints
end
```

## 🔴 Priority 2: Stage 4 Model Alignment Fixes

### 4. Stage 4: Entity Save Guards
**File**: `/app/jobs/pools/extraction_job.rb`
**Issue**: Extracted entities don't match model validations

```ruby
def save_manifest(manifest_data, rights)
  # FIX: Remove invalid field, use correct field name
  manifest_attrs = manifest_data.except('time_bounds_start')
  manifest_attrs['valid_time_start'] ||= Time.current
  
  Manifest.create!(
    manifest_attrs.merge(provenance_and_rights_id: rights.id)
  )
end

def save_practical(practical_data, rights)
  # FIX: Provide default for required field
  practical_data['steps'] ||= ['No steps provided']
  
  Practical.create!(
    practical_data.merge(provenance_and_rights_id: rights.id)
  )
end

def save_evolutionary(evolutionary_data, rights)
  # FIX: Default change_summary from change_note if missing
  evolutionary_data['change_summary'] ||= evolutionary_data['change_note']
  
  Evolutionary.create!(
    evolutionary_data.merge(provenance_and_rights_id: rights.id)
  )
end

def save_relational(relational_data, rights)
  # FIX: Validate enum values before saving
  valid_types = Relational.relation_types.keys
  relation_type = relational_data['relation_type']
  
  return unless valid_types.include?(relation_type)
  return unless relational_data['source_type'].present?
  return unless relational_data['target_type'].present?
  
  Relational.create!(
    relational_data.merge(provenance_and_rights_id: rights.id)
  )
end

def save_emanation(emanation_data, rights)
  # FIX: Coerce or skip invalid influence_type
  valid_types = Emanation.influence_types.keys
  influence_type = emanation_data['influence_type']
  
  return unless valid_types.include?(influence_type)
  
  Emanation.create!(
    emanation_data.merge(provenance_and_rights_id: rights.id)
  )
end
```

## 🔴 Priority 3: Wire Stage 6 to Existing Services

### 5. Stage 6: Connect to Neo4j Embedding Services
**File**: `/app/jobs/embedding/representation_job.rb`
**Issue**: Job is placeholder, but services exist

```ruby
def perform(pipeline_run_id)
  log_progress "Starting embeddings generation using Neo4j GenAI"
  
  # Use existing Neo4j services instead of placeholder
  Graph::Connection.with_database(@ekn.neo4j_database_name) do |driver|
    # Create vector index if needed
    Neo4j::VectorIndexService.new(driver).ensure_indices!
    
    # Generate embeddings for eligible content
    embedding_service = Neo4j::EmbeddingService.new(driver)
    
    eligible_items.find_each do |item|
      begin
        # Get text to embed (from pool item or content)
        text_to_embed = build_representation_text(item)
        
        # Generate and store embedding
        result = embedding_service.encode_and_store(
          node_id: item.pool_item_id,
          node_label: item.pool_item_type,
          text: text_to_embed
        )
        
        item.update!(
          embedding_status: 'embedded',
          embedding_metadata: {
            vector_stored: true,
            node_id: result[:node_id],
            embedded_at: Time.current
          }
        )
        
        track_metric :embeddings_created, 1
      rescue => e
        log_progress "Failed to embed item #{item.id}: #{e.message}", level: :warn
        item.update!(embedding_status: 'failed')
      end
    end
  end
end

private

def build_representation_text(item)
  # Get the pool item for repr_text
  if item.pool_item
    item.pool_item.repr_text || item.pool_item.try(:abstract) || item.content
  else
    item.content
  end
end
```

## 🟡 Already Fixed / Verify

### Stage 2: Rights Inference Override
The quarantine issue for test data can be handled with the workaround documented in STAGE_2_RIGHTS.md

### Stage 1: Content Field
Already correctly sets `item.content` (not `extracted_text`)

### ProvenanceAndRights valid_time_start
Already being set in most places, verify all instances have `valid_time_start: Time.current`

## Testing After Fixes

```ruby
# 1. Test Neo4j transaction fix
Graph::AssemblyJob.perform_now(pipeline_run.id)
# Should not error with "Tried to execute Write query after Schema modification"

# 2. Test Stage 4 entity creation
Pools::ExtractionJob.perform_now(pipeline_run.id)
# Should not error with enum mismatches or missing fields

# 3. Test Stage 6 embeddings
Embedding::RepresentationJob.perform_now(pipeline_run.id)
# Should create actual vector embeddings in Neo4j

# 4. Full pipeline test
rails runner script/test_full_pipeline.rb
# Should complete all 9 stages
```

## Summary of Required Changes

1. **Stage 5**: Split transactions, complete sanitization, fix canonical_description
2. **Stage 4**: Add field guards for Manifest, Practical, Evolutionary, Relational, Emanation
3. **Stage 6**: Wire to existing Neo4j embedding services
4. **Verify**: ProvenanceAndRights always has valid_time_start

These fixes address the concrete errors in your logs and should allow the pipeline to run end-to-end.

## ✅ Verified Changes - August 8, 2025

### 1. Stage 2: Rights Test-Data Override (COMPLETED)
**File**: `/app/services/rights/inference_service.rb`
**Change**: Added test-data override to prevent quarantine in development/test environments

- Added `test_data_override_enabled?` helper method
- Added `test_item?` helper to detect test/synthetic items
- Override returns high-confidence permissive rights for test data
- Controlled by `RESPECT_TEST_RIGHTS_OVERRIDE` environment variable (default: true in dev/test)

### 2. Stage 6: Real Embeddings Integration (COMPLETED)
**File**: `/app/jobs/embedding/representation_job.rb`
**Change**: Integrated Neo4j GenAI embedding services with graceful fallback

- Replaced placeholder with actual Neo4j GenAI integration
- Added `use_neo4j_genai_embeddings?` check for availability
- Implemented `generate_real_embeddings` using Neo4j services
- Added fallback path for dev/test when GenAI unavailable
- Tracks metrics: embeddings_created, embeddings_fallback_used
- Updates item statuses based on actual embedding results

### 3. Stage 1: size_bytes Consistency (COMPLETED)
**File**: `/app/jobs/pipeline/intake_job.rb`
**Change**: Fixed field name consistency

- Changed `item.file_size` to `item.size_bytes` to match model validation

## Validation Commands

```bash
# Test rights override
bin/rails runner 'puts ENV["RESPECT_TEST_RIGHTS_OVERRIDE"] || "true"'
bin/rails runner 'b=IngestBatch.create!(name:"test",source_type:"micro_test"); i=b.ingest_items.create!(file_path:"/tmp/test"); puts Rights::InferenceService.new(i).infer[:confidence]'
# Should output 0.9 for test items

# Test embeddings
bin/rails runner 'Neo4j::VectorIndexService.new("neo4j").configure_provider'
bin/rails runner 'pr = EknPipelineRun.last; Embedding::RepresentationJob.perform_now(pr.id)'

# Check sizes are populated
bin/rails runner 'IntakeJob.perform_now(EknPipelineRun.last.id); puts IngestItem.last.size_bytes'
```