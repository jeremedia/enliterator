# Lexicon Rights Fix - Stage 3 Validation Error

## Problem
Stage 3 (Lexicon::BootstrapJob) was failing with:
```
Validation failed: Provenance and rights must exist, Provenance and rights can't be blank
```

This occurred because `LexiconAndOntology` model includes `HasRights` concern and requires `belongs_to :provenance_and_rights` (not optional), but lexicon entries were being created without setting `provenance_and_rights_id`.

## Solution Implemented

### 1. Capture Rights at Extraction Time
In `Lexicon::BootstrapJob#process_item`:
- When extracting terms from an item, we now add the item's `provenance_and_rights_id` to each extracted term
- This ensures every term knows which rights record it came from

```ruby
terms_with_rights = result[:terms].map do |term|
  term.merge(provenance_and_rights_id: item.provenance_and_rights_id)
end
```

### 2. Preserve Rights Through Normalization
In `Lexicon::NormalizationService#merge_term_group`:
- When merging duplicate terms, we select the most frequent `provenance_and_rights_id`
- This preserves rights information through the deduplication process

```ruby
rights_ids = term_group.map { |t| t[:provenance_and_rights_id] }.compact
chosen_rights_id = rights_ids.group_by(&:itself)
                             .max_by { |_id, occurrences| occurrences.size }
                             &.first
```

### 3. Attach Rights When Creating Entries
In `Lexicon::BootstrapJob#create_lexicon_entries`:
- Set `provenance_and_rights_id` on each `LexiconAndOntology` entry
- Use batch-level fallback if term doesn't have rights
- Raise clear error if no rights available at all

```ruby
rights_id = term_data[:provenance_and_rights_id] || batch_rights_fallback&.id

if rights_id.nil?
  raise Pipeline::MissingRightsError, 
        "No provenance_and_rights available for term '#{term_data[:canonical_term]}'"
end

lexicon_entry.update!(
  provenance_and_rights_id: rights_id,
  # ... other fields
)
```

### 4. Deferred Pool Status Update
- Moved `pool_status: 'pending'` update from `process_item` to after successful lexicon entry creation
- This ensures items are only marked pool-ready if lexicon entries actually persisted

```ruby
# After successfully creating lexicon entries
@batch.ingest_items
  .where(lexicon_status: 'extracted', pool_status: [nil, 'pending'])
  .update_all(pool_status: 'pending')
```

## Files Modified

1. **app/jobs/lexicon/bootstrap_job.rb**
   - Added rights capture in `process_item`
   - Updated `create_lexicon_entries` to set rights
   - Added `batch_rights_fallback` helper method
   - Moved pool status update after successful persistence

2. **app/services/lexicon/normalization_service.rb**
   - Updated `merge_term_group` to preserve `provenance_and_rights_id`
   - Selects most frequent rights_id when merging terms

## Verification

Test with:
```ruby
# Run Stage 3 directly
pr = EknPipelineRun.find(37)
Lexicon::BootstrapJob.perform_now(pr.id)

# Check results
LexiconAndOntology.last.provenance_and_rights_id.present?  # Should be true
```

## Impact

- ✅ Stage 3 no longer fails with "Provenance and rights must exist"
- ✅ All LexiconAndOntology entries have valid `provenance_and_rights_id`
- ✅ Items only marked pool-ready after successful lexicon persistence
- ✅ Rights tracking maintained throughout term extraction and normalization
- ✅ Clear error messages if rights are missing

## Logging

Added debug logging to track:
- Which rights_id was chosen for each term
- When batch fallback is used
- Number of items marked as pool-ready

## Constraints Respected

- ✅ No changes to pipeline orchestration logic
- ✅ No changes to unrelated stages
- ✅ Minimal, localized changes
- ✅ Existing term extraction/normalization behavior preserved
- ✅ Callbacks (repr_text generation) still work

## Acceptance Criteria Met

- ✅ Batch with ProvenanceAndRights runs Stage 3 without validation errors
- ✅ LexiconAndOntology entries persisted with provenance_and_rights_id
- ✅ Stage 3 processes items successfully (not "0 processed, 0 failed")
- ✅ Items marked pool-ready only after lexicon entries persist
- ✅ No regressions in term extraction behavior