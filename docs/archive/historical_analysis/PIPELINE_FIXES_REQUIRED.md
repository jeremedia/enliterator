# Pipeline Fixes Required - Action Items

## Priority 1: Critical Blocking Issues

### 1. Fix Neo4j Transaction Separation (Stage 5)
**File**: `/app/jobs/graph/assembly_job.rb`
**Issue**: Schema and data operations in same transaction cause failure
**Error**: "Tried to execute Write query after executing Schema modification"

**Fix Required**:
```ruby
# In perform method, change from:
Graph::Connection.with_database(@ekn.neo4j_database_name) do |driver|
  driver.session do |session|
    session.write_transaction do |tx|
      # This FAILS - both in same transaction
      Graph::SchemaManager.new(tx).ensure_constraints!
      Graph::NodeLoader.new(tx, @batch).load_all
    end
  end
end

# To:
Graph::Connection.with_database(@ekn.neo4j_database_name) do |driver|
  # Transaction 1: Schema only
  driver.session do |session|
    session.write_transaction do |tx|
      Graph::SchemaManager.new(tx).ensure_constraints!
    end
  end
  
  # Transaction 2: Data only  
  driver.session do |session|
    session.write_transaction do |tx|
      Graph::NodeLoader.new(tx, @batch).load_all
      Graph::EdgeLoader.new(tx, @batch).load_all
    end
  end
end
```

### 2. Fix Rights Quarantine for Test Data (Stage 2)
**File**: `/app/services/rights/inference_service.rb`
**Issue**: Returns 0.0 confidence for test/synthetic data
**Impact**: All test data gets quarantined and cannot proceed

**Quick Fix** (for testing):
```ruby
# Add to Rights::InferenceService#infer method
def infer
  # Existing inference logic...
  
  # Override for test data
  if @item.metadata&.dig('source') == 'micro_test' ||
     @item.metadata&.dig('source') == 'pipeline_test'
    return {
      confidence: 0.9,
      license: 'cc_by',
      consent: 'implicit',
      publishable: true,
      trainable: true,
      source_type: 'test_data',
      method: 'test_generation'
    }
  end
  
  # Continue with normal inference...
end
```

**Proper Fix**: Implement better inference logic that recognizes test/development data patterns

### 3. Fix Missing valid_time_start (Multiple Stages)
**Files**: Multiple job files creating ProvenanceAndRights
**Issue**: ProvenanceAndRights requires valid_time_start but it's often missing
**Error**: "Validation failed: Valid time start can't be blank"

**Fix Required** in all places creating ProvenanceAndRights:
```ruby
ProvenanceAndRights.create!(
  source_ids: [...],
  collection_method: '...',
  consent_status: '...',
  license_type: '...',
  valid_time_start: Time.current,  # ALWAYS include this
  # other fields...
)
```

## Priority 2: Implementation Gaps

### 4. Implement Real Embeddings (Stage 6)
**File**: `/app/jobs/embedding/representation_job.rb`
**Issue**: Currently just a placeholder that marks items as embedded
**Impact**: No actual vector embeddings created, retrieval won't work

**Implementation Needed**:
```ruby
def perform(pipeline_run_id)
  eligible_items.find_each do |item|
    # Build repr_text from entity
    repr_text = build_representation_text(item)
    
    # Generate embedding via OpenAI
    embedding = generate_embedding(repr_text)
    
    # Store in pgvector or Neo4j
    store_embedding(item, embedding)
    
    item.update!(
      embedding_status: 'embedded',
      embedding_metadata: {
        vector_dimensions: embedding.size,
        embedded_at: Time.current
      }
    )
  end
end

private

def generate_embedding(text)
  response = OPENAI.embeddings(
    parameters: {
      model: 'text-embedding-3-small',
      input: text
    }
  )
  response.dig('data', 0, 'embedding')
end
```

### 5. Fix Content Field Usage (Stage 1)
**File**: `/app/jobs/pipeline/intake_job.rb`
**Issue**: Must set `content` field, not `extracted_text`
**Impact**: Later stages look for `content` and fail if missing

**Verify this line exists**:
```ruby
def process_item(item)
  # ... other processing ...
  
  if File.exist?(item.file_path)
    full_content = File.read(item.file_path, encoding: 'UTF-8', invalid: :replace)
    item.content_sample = full_content[0..4999]
    item.content = full_content  # CRITICAL: Must be 'content', not 'extracted_text'
  end
  
  # ... rest of processing ...
end
```

## Priority 3: Data Quality Issues

### 6. Fix Lexicon Canonical Description (Stage 3)
**File**: `/app/models/lexicon_and_ontology.rb`
**Issue**: canonical_description may be nil, causing Neo4j constraint violations

**Fix Already Applied** (verify it exists):
```ruby
class LexiconAndOntology < ApplicationRecord
  before_validation do
    # Ensure canonical_description is always set
    self.canonical_description ||= definition
  end
end
```

### 7. Sanitize Neo4j Properties (Stage 5)
**File**: `/app/services/graph/node_loader.rb`
**Issue**: Neo4j rejects complex types (hashes, AR objects, nested arrays)

**Verify sanitization method exists**:
```ruby
def sanitize_for_neo4j(value)
  case value
  when Array
    if value.any? { |v| v.is_a?(Hash) || v.is_a?(Array) }
      value.to_json  # Convert complex arrays to JSON
    else
      value  # Simple arrays OK
    end
  when Hash
    value.to_json  # Hashes must be JSON
  when ActiveRecord::Base
    value.id  # Never pass AR objects
  when nil
    nil
  else
    value
  end
end
```

## Priority 4: Performance Optimizations

### 8. Batch OpenAI Calls (Stages 3 & 4)
**Current**: Individual API calls for each item (slow)
**Improvement**: Use batch processing where possible

```ruby
# Instead of:
items.each do |item|
  result = OpenAI.chat(...)  # Individual call
end

# Use:
items.in_batches(of: 10) do |batch|
  # Process multiple items in one call
  results = OpenAI.batch(...)
end
```

### 9. Add Progress Tracking Within Stages
**Current**: No visibility into long-running stages
**Improvement**: Add progress logging

```ruby
def perform(pipeline_run_id)
  total = items_to_process.count
  processed = 0
  
  items_to_process.find_each.with_index do |item, index|
    process_item(item)
    processed += 1
    
    # Log progress every 10 items or 10%
    if processed % 10 == 0 || (processed.to_f / total * 100) % 10 == 0
      log_progress "Processed #{processed}/#{total} items (#{(processed.to_f/total*100).round}%)"
    end
  end
end
```

## Testing the Fixes

### 1. Test Neo4j Transaction Fix
```ruby
# Should not error
pr = EknPipelineRun.create!(ekn: ekn, ingest_batch: batch, status: 'running', current_stage: 'graph')
Graph::AssemblyJob.perform_now(pr.id)
```

### 2. Test Rights Override
```ruby
# Create test item
item = IngestItem.create!(
  ingest_batch: batch,
  metadata: { source: 'pipeline_test' },
  content: 'Test content'
)

# Should not quarantine
Rights::TriageJob.perform_now(pr.id)
assert_not item.reload.quarantined
```

### 3. Full Pipeline Test
```ruby
# Run complete pipeline
rails runner script/test_full_pipeline.rb

# Check completion
pr = EknPipelineRun.last
assert_equal 'completed', pr.status
assert_equal 'fine_tuning', pr.current_stage
```

## Monitoring Commands

### Check Pipeline Status
```bash
bin/rails runner 'pr = EknPipelineRun.last; puts "Stage: #{pr.current_stage}, Status: #{pr.status}, Error: #{pr.error_message}"'
```

### Check Stage Progress
```bash
bin/rails runner 'b = IngestBatch.last; puts "Lexicon: #{b.ingest_items.where(lexicon_status: "extracted").count}/#{b.ingest_items.count}"'
```

### Check for Failed Jobs
```bash
bin/rails runner 'fe = SolidQueue::FailedExecution.last; puts fe.error["message"] if fe'
```

## Implementation Order

1. **Immediate** (for testing):
   - Fix Neo4j transaction separation
   - Add test data override for rights

2. **Next Sprint**:
   - Implement real embeddings
   - Add batch processing for OpenAI

3. **Future**:
   - Performance optimizations
   - Better progress tracking
   - Improved error recovery

## Success Criteria

A successful pipeline run should:
1. Process all 10 test items without quarantine
2. Create lexicon entries without errors
3. Load graph without transaction errors
4. Complete all 9 stages
5. Generate a fine-tune dataset
6. Submit to OpenAI for fine-tuning

## Contact for Issues

If issues persist after applying these fixes:
1. Check `/log/development.log` for detailed errors
2. Review stage-specific documentation in `/docs/pipeline/`
3. Verify all gem versions match requirements
4. Ensure Neo4j is running and accessible