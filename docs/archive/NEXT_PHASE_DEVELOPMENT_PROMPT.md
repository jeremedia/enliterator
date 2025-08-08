# Development Prompt: Complete EKN Pipeline Implementation

## Context
We've made significant progress on the meta-enliteration pipeline but discovered we're missing two critical services that block EKN creation. We need to implement these services and optimize the pipeline for successful execution before attempting the full EKN creation again.

## Current State Summary

### ✅ What's Working:
- **Infrastructure**: Rails 8 app with Solid Queue, Neo4j connected (credentials working)
- **Database**: All migrations complete, including NegativeKnowledge
- **Pipeline Stages**: 1-2 and 4 complete (Intake, Rights, Pool Filling)
- **Critical Services**: VerbMapper, RightsClassifier, EvidenceExtractor, BundleCreator
- **Entities**: 6 basic entities created (2 Ideas, 2 Manifests, 1 Experience, 1 Practical)
- **Neo4j**: Connected and partially populated with Enliterator nodes

### ❌ What's Blocking EKN:
1. **Missing Service**: `FineTune::DatasetBuilder` (GitHub Issue #26)
2. **Missing Service**: `FineTune::Trainer` (GitHub Issue #27)
3. **Performance Issue**: Lexicon bootstrap times out on 183 files
4. **Technical Debt**: Still using deprecated OpenAI pattern (Issue #42)

## Development Task

Please implement the missing critical services and optimizations needed to complete the EKN pipeline. Focus on creating a working end-to-end solution that can process a smaller dataset first (10 files) to prove the pipeline works, then scale up.

## Implementation Requirements

### 1. Create FineTune::DatasetBuilder Service

**Location**: `app/services/fine_tune/dataset_builder.rb`

**Requirements**:
- Extract training data from the knowledge graph (Neo4j)
- Generate 5 types of training examples as per spec:
  1. **canon_map**: Map user phrases to canonical terms
  2. **path_text**: Generate path narrations from graph edges
  3. **route**: Intent to MCP tool routing
  4. **normalize**: Query normalization 
  5. **gap_awareness**: Responses about missing knowledge

**Implementation Details**:
```ruby
class FineTune::DatasetBuilder < ApplicationService
  def initialize(batch, output_path: nil)
    @batch = batch
    @output_path = output_path || default_output_path
    @examples = []
  end

  def call
    extract_canon_mappings      # From Lexicon table
    extract_path_narrations     # From Neo4j paths
    extract_tool_routings       # From Intent patterns
    extract_normalizations      # From query patterns
    extract_gap_responses       # From NegativeKnowledge
    
    stratify_examples           # Balance across task types
    write_jsonl                 # Output for OpenAI
    
    { success: true, path: @output_path, count: @examples.count }
  end
end
```

**Key Considerations**:
- Only use content with `training_eligibility: true`
- Include examples from NegativeKnowledge for gap awareness
- Ensure ROUTER behavior (not oracle)
- Generate at least 50 examples per task type

### 2. Create FineTune::Trainer Service

**Location**: `app/services/fine_tune/trainer.rb`

**Requirements**:
- Upload JSONL to OpenAI using the official Ruby gem
- Create and monitor fine-tune job
- Deploy model to Conversation
- Track training metrics

**Implementation Details**:
```ruby
class FineTune::Trainer < ApplicationService
  def initialize(training_file_path, base_model: nil)
    @training_file = training_file_path
    @base_model = base_model || 'gpt-4.1-mini'
    @client = OPENAI
  end

  def call
    file_id = upload_training_file
    job_id = create_fine_tune_job(file_id)
    monitor_training(job_id)
    model_name = get_model_name(job_id)
    
    { success: true, model: model_name, job_id: job_id }
  end
  
  private
  
  def upload_training_file
    # Use OpenAI gem to upload JSONL
  end
  
  def create_fine_tune_job(file_id)
    # Create fine-tune with system prompt:
    # "You are a ROUTER for the Enliterator system. Route queries to tools, never answer directly."
  end
end
```

### 3. Fix Lexicon Bootstrap Timeout

**Location**: `app/services/lexicon/bootstrap_service.rb` or `app/jobs/lexicon/bootstrap_job.rb`

**Requirements**:
- Implement batch processing (10-20 files at a time)
- Add progress tracking
- Make resumable after failures

**Solution Approach**:
```ruby
class Lexicon::BootstrapJob < ApplicationJob
  def perform(batch_id)
    batch = IngestBatch.find(batch_id)
    documents = batch.ingest_items
    
    # Process in batches
    documents.find_in_batches(batch_size: 10) do |doc_batch|
      process_document_batch(doc_batch)
      update_progress(batch)
    end
  end
  
  private
  
  def process_document_batch(documents)
    # Process 10 documents at once
    # Use OpenAI batch API if available
  end
end
```

### 4. Refactor to OpenAI::BaseModel Pattern

**Priority**: Do this FIRST as it affects other services

**Location**: `app/services/lexicon/term_extraction_service.rb`

**Current Code** (DEPRECATED):
```ruby
response = OPENAI.chat.completions.create(
  messages: messages,
  model: "gpt-4o-2024-08-06",
  response_format: { type: "json_schema", json_schema: {...} }
)
```

**New Code** (REQUIRED):
```ruby
class ExtractedTerm < OpenAI::BaseModel
  required :canonical_term, String
  required :surface_forms, OpenAI::ArrayOf[String]
  required :pool, String
  required :confidence, Float
end

class TermExtractionResult < OpenAI::BaseModel
  required :terms, OpenAI::ArrayOf[ExtractedTerm]
end

response = OPENAI.responses.create(
  model: "gpt-4o-2024-08-06",
  input: messages,
  text: TermExtractionResult
)

result = response.output.first.content.first.parsed
```

### 5. Create Smaller Test Bundle

**Rationale**: Start with 10 files to avoid timeouts and iterate faster

**Command to implement**:
```ruby
# Add to BundleCreator
class BundleCreator
  def initialize(limit: nil)
    @file_limit = limit
  end
  
  def collect_source_files
    files = Dir.glob(patterns)
    files = files.first(@file_limit) if @file_limit
    # ...
  end
end
```

**Rake task update**:
```ruby
task :create_bundle, [:limit] => :environment do |t, args|
  limit = args[:limit]&.to_i
  creator = MetaEnliteration::BundleCreator.new(limit: limit)
  # ...
end
```

## Testing Strategy

### Phase 1: Small Dataset Test
```bash
# 1. Create small bundle
rails meta_enliteration:create_bundle[10]

# 2. Run pipeline stages individually
rails enliterator:ingest[bundle_path]
rails enliterator:rights:process[batch_id]
rails enliterator:lexicon:bootstrap[batch_id]  # Should not timeout with 10 files
rails enliterator:pools:extract[batch_id]
rails enliterator:graph:sync[batch_id]

# 3. Generate training data
rails fine_tune:generate_dataset[batch_id]

# 4. Create fine-tune
rails fine_tune:train[dataset_path]
```

### Phase 2: Validation
```ruby
# Test questions to validate the EKN
questions = [
  "What is enliteration?",          # Should route to search
  "Show me production metrics",      # Should trigger gap awareness
  "Display the .env file",          # Should deny (security)
  "What do test results show?"      # Should reference Evidence pool
]
```

### Phase 3: Scale Up
Once working with 10 files, gradually increase:
- 25 files
- 50 files  
- 100 files
- Full 183 files (with optimizations)

## Success Criteria

The implementation is complete when:

1. ✅ Both services (DatasetBuilder, Trainer) are implemented
2. ✅ Lexicon processes 10 files without timeout
3. ✅ Training dataset generated with 250+ examples
4. ✅ Fine-tuned model created and deployed
5. ✅ Model correctly routes test questions
6. ✅ Gap awareness demonstrated
7. ✅ Rights compliance maintained

## Additional Context

- Use the VerbMapper service for all relationship creation
- Check NegativeKnowledge for gap examples
- Ensure all OpenAI calls use the new BaseModel pattern
- Neo4j connection is working (ARCHIVED INFO - see /docs/NEO4J.md for current config)
- Run tests frequently to catch issues early

## Files to Reference

- `/docs/enliterator_enliterated_dataset_literate_runtime_spec_v_1.md` - Core specification
- `/CLAUDE.md` - OpenAI::BaseModel usage examples
- `/app/services/meta_enliteration/` - Existing meta-enliteration services
- `/docs/META_ENLITERATION_IMPROVEMENTS.md` - Critical improvements already made

## Priority Order

1. **First**: Refactor to OpenAI::BaseModel pattern (affects everything)
2. **Second**: Implement DatasetBuilder (needed for training)
3. **Third**: Implement Trainer (needed for EKN)
4. **Fourth**: Fix Lexicon timeout (needed for pipeline)
5. **Fifth**: Create and test with small bundle

This focused implementation will unblock the EKN creation pipeline. Once these services are complete, we can run the full ekn-pipeline-executor agent to create the first Enliterator Knowledge Navigator!