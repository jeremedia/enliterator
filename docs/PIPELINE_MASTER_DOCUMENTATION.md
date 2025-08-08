# Enliterator Pipeline Master Documentation

## Overview

The Enliterator pipeline is a 9-stage zero-touch data processing system that transforms raw content into an Enliterated Knowledge Navigator (EKN). This document provides a comprehensive technical analysis of the pipeline implementation as of August 2025.

## Pipeline Architecture

### Core Components

1. **Base Job Framework** (`Pipeline::BaseJob`)
   - Provides consistent orchestration via `around_perform` wrapper
   - Automatic error handling with retry logic (3 attempts, polynomial backoff)
   - EKN context setting for API call tracking
   - Stage validation and metrics collection
   - Comprehensive logging with stage-specific labels

2. **Data Models**
   - `EknPipelineRun`: Tracks pipeline execution state
   - `IngestBatch`: Groups items for processing
   - `IngestItem`: Individual content items with stage-specific status fields
   - `Ekn`: Top-level Knowledge Navigator entity

3. **Stage Status Tracking**
   Each IngestItem has independent status fields for each stage:
   - `triage_status`: pending, completed, quarantined, failed
   - `lexicon_status`: pending, extracted, failed, skipped
   - `pool_status`: pending, extracted, failed, skipped
   - `graph_status`: pending, assembled, failed, skipped
   - `embedding_status`: pending, embedded, failed, skipped

## Pipeline Stages

### Stage 0: Frame the Mission
**Status**: Not explicitly implemented as a job
- Configuration and goal setting phase
- Handled during EKN and IngestBatch creation

### Stage 1: Intake (`Pipeline::IntakeJob`)
**Purpose**: Process raw files and prepare for rights triage

**Code Flow**:
```ruby
def perform(pipeline_run_id)
  @batch.ingest_items.find_each do |item|
    # Detect media type from file extension
    item.media_type = detect_media_type(item.file_path)
    
    # Calculate file hash for deduplication
    item.file_hash = calculate_file_hash(item.file_path)
    
    # Read file content
    full_content = File.read(item.file_path)
    item.content_sample = full_content[0..4999]  # For rights inference
    item.content = full_content  # Full content for processing
    
    item.triage_status = 'pending'
    item.save!
  end
end
```

**Critical Fields Set**:
- `media_type`: text, code, config, data, document, etc.
- `file_hash`: SHA256 for deduplication
- `content`: Full text content (REQUIRED for later stages)
- `content_sample`: First 5000 chars for rights inference

### Stage 2: Rights & Provenance (`Rights::TriageJob`)
**Purpose**: Infer rights and attach ProvenanceAndRights records

**Code Flow**:
```ruby
def triage_item(item)
  # Use inference service to determine rights
  inferred_rights = Rights::InferenceService.new(item).infer
  
  if inferred_rights[:confidence] < 0.7
    quarantine_item(item, inferred_rights)
  else
    attach_rights(item, inferred_rights)
  end
end

def quarantine_item(item, inferred_rights)
  item.update!(
    quarantined: true,
    triage_status: 'quarantined',
    quarantine_reason: "Low confidence: #{inferred_rights[:confidence]}"
  )
  
  # Still create ProvenanceAndRights record
  rights_record = ProvenanceAndRights.create!(
    source_ids: [item.source_hash],
    collection_method: inferred_rights[:method] || 'file_system',
    consent_status: map_consent_status(inferred_rights),
    license_type: map_license_type(inferred_rights[:license]),
    valid_time_start: Time.current,  # REQUIRED field
    publishability: false,
    training_eligibility: false
  )
  
  item.update!(provenance_and_rights_id: rights_record.id)
end
```

**CRITICAL ISSUE**: Test data gets quarantined with confidence 0.0

### Stage 3: Lexicon Bootstrap (`Lexicon::BootstrapJob`)
**Purpose**: Extract canonical terms and surface forms

**Code Flow**:
```ruby
def process_item(item)
  return if item.content.blank?  # REQUIRES content field
  
  # Extract terms via OpenAI
  result = Lexicon::TermExtractionService.new(
    content: item.content,
    metadata: item.metadata
  ).extract
  
  # Normalize and deduplicate
  normalized = Lexicon::NormalizationService.new(
    terms: result[:terms],
    batch_context: @batch
  ).normalize
  
  # Create LexiconAndOntology entries
  normalized[:canonical_terms].each do |term_data|
    lexicon_entry = LexiconAndOntology.create!(term_data)
    contributing_item_ids << item.id if lexicon_entry.persisted?
  end
end

# Stage 3 Hardening - track contributing items
item.update!(
  lexicon_status: 'extracted',
  pool_status: contributing_item_ids.include?(item.id) ? 'pending' : 'skipped',
  lexicon_metadata: { 
    source_item_ids: [item.id],  # Track for lineage
    terms_count: result[:terms].size
  }
)
```

**Key Features**:
- Stage 3 hardening tracks `source_item_ids`
- Only items contributing new terms marked pool-ready
- Duplicate terms tracked with skip reason

### Stage 4: Pool Filling (`Pools::ExtractionJob`)
**Purpose**: Extract entities for Ten Pool Canon

**Code Flow**:
```ruby
def process_item(item)
  # Extract entities via OpenAI
  entities = Pools::EntityExtractionService.new(
    content: item.content,
    lexicon_context: build_lexicon_context
  ).extract
  
  # Create default rights for entities
  default_rights = ProvenanceAndRights.find_or_create_by!(
    source_ids: ["pipeline_extraction_#{@batch.id}"],
    collection_method: "openai_extraction",
    consent_status: "implicit_consent",
    license_type: "custom",
    valid_time_start: Time.current  # CRITICAL: Required field
  )
  
  # Save entities to pool tables
  entities.each do |entity_data|
    pool_class = entity_data[:pool].constantize
    entity = pool_class.create!(
      entity_data[:attributes].merge(
        provenance_and_rights_id: default_rights.id
      )
    )
  end
  
  item.update!(
    pool_status: 'extracted',
    graph_status: 'pending'
  )
end
```

**Note**: Relations extracted but not saved (need entity resolution)

### Stage 5: Graph Assembly (`Graph::AssemblyJob`)
**Purpose**: Load nodes and edges to Neo4j

**Code Flow**:
```ruby
def perform(pipeline_run_id)
  # Ensure EKN database exists
  Graph::DatabaseManager.new(@ekn).ensure_database!
  
  Graph::Connection.with_database(@ekn.neo4j_database_name) do |driver|
    # CRITICAL: Schema in separate transaction
    driver.session do |session|
      session.write_transaction do |tx|
        Graph::SchemaManager.new(tx).ensure_constraints!
      end
    end
    
    # Data loading in new transaction
    driver.session do |session|
      session.write_transaction do |tx|
        nodes = Graph::NodeLoader.new(tx, @batch).load_all
        edges = Graph::EdgeLoader.new(tx, @batch).load_all
        duplicates = Graph::Deduplicator.new(tx).resolve_duplicates
      end
    end
  end
end
```

**CRITICAL BUG**: "Tried to execute Write query after executing Schema modification"
- Schema and data operations MUST be in separate transactions

### Stage 6: Representations & Retrieval (`Embedding::RepresentationJob`)
**Purpose**: Build embeddings and vector indices

**Current Implementation**:
```ruby
def perform(pipeline_run_id)
  # SIMPLIFIED PLACEHOLDER
  eligible_items.find_each do |item|
    item.update!(embedding_status: 'embedded')
  end
end
```

**MAJOR GAP**: Missing actual implementation
- Should generate repr_text for entities
- Should create path sentences from graph
- Should use OpenAI embeddings API or Neo4j GenAI
- Should create vector indices for retrieval

### Stage 7: Literacy Scoring (`Literacy::ScoringJob`)
**Purpose**: Calculate enliteracy score and identify gaps

**Code Flow**:
```ruby
def calculate_score
  coverage = calculate_coverage_score      # 0-100
  completeness = calculate_completeness_score  # 0-100
  density = calculate_density_score        # 0-100
  quality = calculate_quality_score        # 0-100
  
  # Weighted average
  enliteracy_score = (
    coverage * 0.3 +
    completeness * 0.3 +
    density * 0.2 +
    quality * 0.2
  )
  
  @batch.update!(
    literacy_score: enliteracy_score,
    literacy_gaps: identify_gaps
  )
end
```

### Stage 8: Deliverables Generation (`Deliverables::GenerationJob`)
**Purpose**: Generate prompt packs and evaluation bundles

**Code Flow**:
```ruby
def perform(pipeline_run_id)
  deliverables = []
  
  deliverables << generate_prompt_pack
  deliverables << generate_evaluation_bundle
  deliverables << generate_summary_report
  
  @batch.update!(
    deliverables: deliverables,
    status: 'completed'
  )
end
```

### Stage 9: Fine-tuning (`FineTune::DatasetBuilderJob`)
**Purpose**: Build training dataset for model fine-tuning

**Code Flow**:
```ruby
def generate_training_examples
  @training_examples = []
  
  # Canonical term mapping
  LexiconAndOntology.find_each do |lexicon|
    lexicon.surface_forms.each do |surface|
      @training_examples << {
        messages: [
          {role: "system", content: "Map to canonical term"},
          {role: "user", content: surface},
          {role: "assistant", content: lexicon.term}
        ]
      }
    end
  end
  
  # Submit to OpenAI
  trainer = FineTune::Trainer.new(
    dataset_path: save_dataset,
    suffix: "enliterator-ekn-#{@ekn.id}"
  )
  result = trainer.call
end
```

**CRITICAL**: Model must support fine-tuning (gpt-4.1-mini-2025-04-14)

## Common Issues and Solutions

### 1. Rights Quarantine Problem
**Issue**: Test data gets quarantined with 0.0 confidence
```ruby
# Fix in test setup:
batch.ingest_items.update_all(
  triage_status: 'completed',
  quarantined: false,
  training_eligible: true,
  publishable: true
)
```

### 2. Content Field Missing
**Issue**: Stages expect `content` field, not `extracted_text`
```ruby
# Ensure IntakeJob sets:
item.content = full_content  # NOT extracted_text
```

### 3. Neo4j Transaction Error
**Issue**: Schema modifications conflict with data operations
```ruby
# WRONG:
session.write_transaction do |tx|
  SchemaManager.new(tx).ensure_constraints!
  NodeLoader.new(tx).load_all  # FAILS
end

# CORRECT:
session.write_transaction do |tx|
  SchemaManager.new(tx).ensure_constraints!
end
session.write_transaction do |tx|
  NodeLoader.new(tx).load_all  # Works
end
```

### 4. Fine-tune Model Support
**Issue**: Not all models support fine-tuning
```ruby
# Supported models (as of August 2025):
- gpt-4.1-mini-2025-04-14  # Works
- gpt-3.5-turbo            # Works
- gpt-5-mini               # Does NOT support fine-tuning
```

### 5. Missing valid_time_start
**Issue**: ProvenanceAndRights requires valid_time_start
```ruby
ProvenanceAndRights.create!(
  # ... other fields ...
  valid_time_start: Time.current  # REQUIRED
)
```

## Performance Characteristics

### Bottlenecks
1. **OpenAI API Calls**: Each item requires multiple API calls
   - Stage 3: 1 call per item for term extraction
   - Stage 4: 1 call per item for entity extraction
   - Stage 9: Batch API for embeddings

2. **Neo4j Operations**: Graph assembly can be slow for large batches

3. **Memory Usage**: Loading all entities for graph assembly

### Typical Timing (10 items)
- Stage 1 (Intake): ~5 seconds
- Stage 2 (Rights): ~10 seconds
- Stage 3 (Lexicon): ~3-5 minutes (OpenAI calls)
- Stage 4 (Pools): ~3-5 minutes (OpenAI calls)
- Stage 5 (Graph): ~30 seconds
- Stage 6 (Embeddings): Currently instant (placeholder)
- Stage 7 (Literacy): ~10 seconds
- Stage 8 (Deliverables): ~5 seconds
- Stage 9 (Fine-tuning): ~1 minute + OpenAI processing

**Total**: ~15-20 minutes for 10 items

## Monitoring and Debugging

### Check Pipeline Status
```ruby
pr = EknPipelineRun.find(id)
puts "Stage: #{pr.current_stage}, Status: #{pr.status}"
puts "Error: #{pr.error_message}" if pr.status == "failed"
```

### Check Stage Progress
```ruby
batch = IngestBatch.find(id)
puts "Lexicon: #{batch.ingest_items.where(lexicon_status: 'extracted').count}"
puts "Pools: #{batch.ingest_items.where(pool_status: 'extracted').count}"
puts "Graph: #{batch.ingest_items.where(graph_status: 'assembled').count}"
```

### Check Job Queue
```ruby
SolidQueue::Job.where("created_at > ?", 5.minutes.ago).pluck(:class_name, :finished_at)
SolidQueue::FailedExecution.order(created_at: :desc).first
```

### API Call Tracking
```ruby
ApiCall.where("created_at > ?", 5.minutes.ago).count
ApiCall.where(ekn_id: ekn.id).group(:endpoint).count
```

## Recommendations

### Immediate Fixes Needed
1. Fix Neo4j transaction separation in Stage 5
2. Implement actual embeddings in Stage 6
3. Fix rights inference for test data
4. Ensure content field is populated correctly

### Architecture Improvements
1. Batch OpenAI calls where possible
2. Implement caching for lexicon lookups
3. Add progress tracking within stages
4. Improve error recovery and partial completion

### Performance Optimizations
1. Parallel processing for independent items
2. Bulk Neo4j operations instead of individual creates
3. Streaming for large content processing
4. Connection pooling for Neo4j

## Conclusion

The pipeline demonstrates solid architectural patterns with proper separation of concerns, comprehensive error handling, and stage isolation. The main issues are:

1. Stage 6 (Embeddings) needs real implementation
2. Neo4j transaction management in Stage 5
3. Rights inference too strict for test data
4. Performance bottlenecks with sequential OpenAI calls

With these fixes, the pipeline should reliably process data from raw content to fine-tuned Knowledge Navigator.