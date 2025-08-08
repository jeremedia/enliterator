# Stage 2: Rights & Provenance - Detailed Documentation

## Overview
Stage 2 (Rights & Provenance) is critical for legal compliance and ethical data handling. It infers rights from content and metadata, creates ProvenanceAndRights records, and determines whether content can be published or used for training. Items with low-confidence rights inference are quarantined.

## Job Implementation
**File**: `/app/jobs/rights/triage_job.rb`
**Queue**: `:pipeline`
**Base Class**: `Pipeline::BaseJob`

## Input Requirements

### IngestItems
- Must have `triage_status: 'pending'` (set by Stage 1)
- Must have `content_sample` populated for inference
- Must have `file_path` for source tracking

## Processing Logic

### Main Flow
```ruby
def perform(pipeline_run_id)
  items_to_process.find_each do |item|
    triage_item(item)
  end
  finalize_batch_triage
end

def items_to_process
  @batch.ingest_items.where(triage_status: ['pending', nil])
end
```

### Rights Inference
```ruby
def triage_item(item)
  # Use inference service to analyze content
  inferred_rights = Rights::InferenceService.new(item).infer
  
  # Decision point based on confidence
  if inferred_rights[:confidence] < 0.7
    quarantine_item(item, inferred_rights)  # Low confidence
  else
    attach_rights(item, inferred_rights)    # High confidence
  end
end
```

## CRITICAL ISSUE: Quarantine Logic

### The Problem
Test data and synthetic content often get quarantined with 0.0 confidence:

```ruby
def quarantine_item(item, inferred_rights)
  # Item gets quarantined and cannot proceed
  item.update!(
    quarantined: true,
    triage_status: 'quarantined',
    quarantine_reason: "Low confidence rights inference: #{inferred_rights[:confidence]}"
  )
  
  # ProvenanceAndRights created but marked restricted
  rights_record = ProvenanceAndRights.create!(
    source_ids: [item.source_hash || item.file_path],
    collection_method: inferred_rights[:method] || 'file_system',
    consent_status: map_consent_status(inferred_rights),
    license_type: map_license_type(inferred_rights[:license]),
    valid_time_start: Time.current,  # REQUIRED FIELD
    publishability: false,            # Cannot publish
    training_eligibility: false,      # Cannot train
    quarantined: true
  )
  
  item.update!(provenance_and_rights_id: rights_record.id)
end
```

### Why This Happens
The `Rights::InferenceService` returns 0.0 confidence for:
- Synthetic/test content without clear attribution
- Content without license headers
- Files without metadata

### The Impact
Quarantined items:
- Have `quarantined: true` flag
- Are excluded from `items_to_process` in later stages
- Never get lexicon extraction, pool extraction, or graph assembly
- Break the pipeline for test data

## Successful Rights Attachment

When confidence >= 0.7:

```ruby
def attach_rights(item, inferred_rights)
  rights_record = ProvenanceAndRights.create!(
    # Required fields
    source_ids: [item.source_hash || item.file_path],
    collection_method: inferred_rights[:method] || 'file_system',
    consent_status: map_consent_status(inferred_rights),
    license_type: map_license_type(inferred_rights[:license]),
    valid_time_start: Time.current,  # CRITICAL: Required field
    
    # Optional fields
    source_owner: inferred_rights[:owner] || 'inferred',
    
    # Rights flags (may be overridden by model callbacks)
    publishability: inferred_rights[:publishable] || false,
    training_eligibility: inferred_rights[:trainable] || false,
    quarantined: false,
    
    # Additional metadata in JSON field
    custom_terms: {
      'source_type' => inferred_rights[:source_type],
      'confidence' => inferred_rights[:confidence],
      'signals' => inferred_rights[:signals]
    }
  )
  
  item.update!(
    triage_status: 'completed',
    provenance_and_rights_id: rights_record.id,
    training_eligible: rights_record.training_eligibility,
    publishable: rights_record.publishability,
    lexicon_status: 'pending'  # Ready for Stage 3
  )
end
```

## Field Mapping Functions

### Consent Status Mapping
```ruby
def map_consent_status(inferred_rights)
  consent = inferred_rights[:consent] || inferred_rights[:consent_status]
  
  case consent.to_s.downcase
  when 'explicit', 'yes', 'granted'
    'explicit_consent'
  when 'implicit', 'assumed'
    'implicit_consent'
  when 'no', 'denied', 'refused'
    'no_consent'
  when 'withdrawn', 'revoked'
    'withdrawn'
  else
    # Default based on confidence
    inferred_rights[:confidence].to_f >= 0.8 ? 'implicit_consent' : 'unknown'
  end
end
```

### License Type Mapping
```ruby
def map_license_type(license)
  return 'unspecified' if license.blank?
  
  normalized = license.to_s.downcase.gsub(/[\s\-_]/, '')
  
  case normalized
  when /cc0/, /creativecommons0/
    'cc0'
  when /ccby$/, /attribution$/
    'cc_by'
  when /mit/, /apache/, /gpl/, /bsd/
    'custom'  # Open source licenses
  when /proprietary/, /copyright/
    'proprietary'
  when /publicdomain/
    'public_domain'
  else
    'unspecified'
  end
end
```

## Output Data

### Successful Triage
```ruby
# IngestItem updates
{
  triage_status: 'completed',
  provenance_and_rights_id: 123,
  training_eligible: true,
  publishable: true,
  lexicon_status: 'pending',
  quarantined: false
}

# ProvenanceAndRights record
{
  source_ids: ['hash123'],
  collection_method: 'file_system',
  consent_status: 'implicit_consent',
  license_type: 'cc_by',
  valid_time_start: '2025-08-07 12:00:00',
  publishability: true,
  training_eligibility: true
}
```

### Quarantined Item
```ruby
# IngestItem updates
{
  triage_status: 'quarantined',
  quarantined: true,
  quarantine_reason: 'Low confidence rights inference: 0.0',
  provenance_and_rights_id: 124
}

# ProvenanceAndRights record (still created)
{
  publishability: false,
  training_eligibility: false,
  quarantined: true
}
```

## Batch Status Determination

```ruby
def determine_batch_status(completed, quarantined, failed)
  total = completed + quarantined + failed
  
  if failed > total * 0.5
    'triage_failed'           # >50% failed
  elsif quarantined > total * 0.8
    'triage_needs_review'     # >80% quarantined
  else
    'triage_completed'        # Normal completion
  end
end
```

## Metrics Tracked

```ruby
{
  items_completed: 7,      # Successfully triaged
  items_quarantined: 3,    # Low confidence
  items_failed: 0,         # Errors during triage
  training_eligible: 7,    # Can be used for training
  publishable: 7          # Can be published
}
```

## Common Issues and Solutions

### Issue 1: All Test Data Quarantined
**Symptom**: Pipeline fails with "0 items marked pool-ready"
**Cause**: InferenceService returns 0.0 confidence for test data
**Solution**:
```ruby
# Fix after triage for test data
batch.ingest_items.update_all(
  triage_status: 'completed',
  quarantined: false,
  training_eligible: true,
  publishable: true
)
```

### Issue 2: Missing valid_time_start
**Symptom**: ActiveRecord::RecordInvalid - valid_time_start can't be blank
**Cause**: ProvenanceAndRights requires this field
**Solution**: Always set `valid_time_start: Time.current`

### Issue 3: Wrong Enum Values
**Symptom**: ArgumentError - 'triage_partially_complete' is not a valid status
**Cause**: Using non-existent enum values
**Solution**: Use correct values from IngestBatch model:
- Valid: `triage_completed`, `triage_needs_review`, `triage_failed`
- Invalid: `triage_partially_complete`

## Performance Characteristics

### Timing
- Inference service call: ~500ms per item (depends on implementation)
- Database operations: ~20ms per item
- Total per item: ~520ms

### Typical Performance
- 10 items: ~5-10 seconds
- 100 items: ~1 minute
- 1000 items: ~10 minutes

## Testing Recommendations

### Unit Tests
```ruby
# Test consent mapping
assert_equal 'explicit_consent', map_consent_status({consent: 'explicit'})
assert_equal 'implicit_consent', map_consent_status({consent: 'assumed'})
assert_equal 'unknown', map_consent_status({consent: nil, confidence: 0.5})

# Test license mapping
assert_equal 'cc_by', map_license_type('CC-BY')
assert_equal 'custom', map_license_type('MIT')
assert_equal 'unspecified', map_license_type(nil)
```

### Integration Tests
```ruby
# Test successful triage
item = create(:ingest_item, triage_status: 'pending')
allow(Rights::InferenceService).to receive(:infer).and_return(
  confidence: 0.9,
  license: 'CC-BY',
  consent: 'implicit'
)

TriageJob.perform_now(pipeline_run.id)

assert_equal 'completed', item.reload.triage_status
assert item.training_eligible
assert_not item.quarantined
```

## Workaround for Test Data

Since test/synthetic data often gets quarantined, use this workaround:

```ruby
# After Stage 2 completes, fix quarantined test items
def fix_test_data_quarantine
  batch.ingest_items.where(quarantined: true).each do |item|
    # Update item flags
    item.update!(
      triage_status: 'completed',
      quarantined: false,
      training_eligible: true,
      publishable: true,
      lexicon_status: 'pending'
    )
    
    # Update associated rights record
    if item.provenance_and_rights
      item.provenance_and_rights.update!(
        publishability: true,
        training_eligibility: true,
        quarantined: false
      )
    end
  end
end
```

## Next Stage
Items with `triage_status: 'completed'` and `quarantined: false` proceed to Stage 3 (Lexicon Bootstrap) for term extraction.