# Lexicon Stage Issues Analysis

## The Problem
Stage 3 (Lexicon) shows multiple failures in the logs but advances to Stage 4 anyway:
- Reports "❌ Stage FAILED: Lexicon stage extracted 0 terms from 10 items!"
- Shows "✅ Lexicon bootstrap complete: 0 processed, 0 failed"
- Pipeline continues to Stage 4 despite the failure

## Root Causes

### 1. Items Already Marked as Extracted
The core issue is in the `items_to_process` query in `Lexicon::BootstrapJob`:

```ruby
def items_to_process
  @batch.ingest_items
    .where(triage_status: 'completed')
    .where(lexicon_status: ['pending', nil])  # ← Problem here
    .where(quarantined: [false, nil])
end
```

**What happens:**
1. First run: Processes 10 items, extracts terms, marks them as `lexicon_status: 'extracted'`
2. Job fails due to validation error
3. Retry attempts: Finds 0 items because all have `lexicon_status: 'extracted'`
4. Processes 0 items "successfully"
5. Validation fails because 0 terms extracted from 10 total items

### 2. Validation Logic Contradiction
The validation in `Pipeline::BaseJob` fails the stage:

```ruby
when "Lexicon::BootstrapJob"
  if metrics[:terms_extracted] == 0 && @batch.ingest_items.count > 0
    raise Pipeline::InvalidDataError, "Lexicon stage extracted 0 terms from #{@batch.ingest_items.count} items!"
  end
```

But the job itself completes successfully (it processed all 0 items it found without error).

### 3. Manual Pipeline Advancement
The pipeline advanced despite failures because we used `script/continue_pipeline.rb` which:
- Checked if all items had `lexicon_status: 'extracted'` → YES
- Ignored that 0 terms were actually extracted
- Manually advanced to Stage 4

## The Sequence of Events

1. **20:13:32** - Stage 3 starts with 10 items
2. **20:18:07** - Fails with "Validation failed: Provenance and rights must exist"
3. **20:18:11** - Retries but finds 0 items (already marked 'extracted')
4. **20:18:11** - "Completes" with 0 processed, validation fails it
5. **20:18:32** - Another retry, same result
6. **Manual intervention** - `continue_pipeline.rb` advances to Stage 4

## Issues to Fix

### 1. Idempotency Problem
The job isn't idempotent - once items are marked 'extracted', retries find nothing to process.

**Solution:** Reset item status when retrying failed stages:
```ruby
def items_to_process
  items = @batch.ingest_items
    .where(triage_status: 'completed')
    .where(quarantined: [false, nil])
  
  # If this is a retry and we had failures, include previously processed items
  if @pipeline_run.retry_count > 0
    items = items.where(lexicon_status: ['pending', nil, 'failed', 'extracted'])
  else
    items = items.where(lexicon_status: ['pending', nil])
  end
  
  items
end
```

### 2. Validation vs Completion Mismatch
The job completes successfully (processed all items it found) but validation fails it.

**Solution:** Check for actual work done, not just item counts:
```ruby
def validate_stage_completion(metrics)
  # For Lexicon, check if terms were actually extracted from eligible items
  when "Lexicon::BootstrapJob"
    eligible_items = @batch.ingest_items
      .where(triage_status: 'completed')
      .where(quarantined: [false, nil])
      .count
    
    if eligible_items > 0 && metrics[:terms_extracted] == 0
      # Only fail if there were eligible items but no terms extracted
      raise Pipeline::InvalidDataError, "Lexicon stage extracted 0 terms from #{eligible_items} eligible items!"
    end
end
```

### 3. Stage Status Tracking
Stages can be marked as both 'failed' and have items marked as 'extracted'.

**Solution:** Clear item statuses when retrying a failed stage:
```ruby
def retry_failed_stage!
  # Reset item statuses for the failed stage
  case current_stage
  when 'lexicon'
    ingest_batch.ingest_items.update_all(
      lexicon_status: 'pending',
      lexicon_metadata: nil
    )
  when 'pools'
    ingest_batch.ingest_items.update_all(
      pool_status: 'pending',
      pool_metadata: nil
    )
  end
  
  # Then queue the retry job
  # ...
end
```

## Why It Still Advanced

The pipeline advanced to Stage 4 despite Stage 3 failures because:

1. **Manual intervention** - We used `continue_pipeline.rb` to force advancement
2. **Item status vs stage status** - Items were marked 'extracted' even though the stage failed
3. **Completion check** - The script only checked if items had the right status, not if extraction was successful

## Recommendations

1. **Make jobs idempotent** - Retries should reprocess items if previous attempts failed
2. **Fix validation logic** - Distinguish between "no items to process" and "processing failed"
3. **Add stage retry logic** - Reset item statuses when retrying failed stages
4. **Improve error messages** - Clearly indicate why a stage failed and what needs fixing
5. **Add extraction success metrics** - Track not just item counts but actual extraction results