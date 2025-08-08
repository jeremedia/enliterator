# Stage 3 Lexicon Hardening

## Overview
Implemented three critical improvements to Stage 3 (Lexicon::BootstrapJob) to make it more robust and precise.

## Changes Implemented

### 1. Source Item ID Propagation
**Problem:** No way to track which items contributed to which lexicon entries after deduplication.

**Solution:** 
- Added `source_item_id` to each extracted term in `process_item`
- `NormalizationService` collects all contributing `source_item_ids` when merging terms
- This enables precise tracking of which items contributed to persisted entries

```ruby
# In process_item
terms_with_rights = result[:terms].map do |term|
  term.merge(
    provenance_and_rights_id: item.provenance_and_rights_id,
    source_item_id: item.id
  )
end

# In NormalizationService#merge_term_group
source_item_ids = term_group.map { |t| t[:source_item_id] }.compact.uniq
```

### 2. Fixed Pool Association
**Problem:** Using `term_data[:pool_type]` which didn't exist, always falling back to 'general'.

**Solution:**
- Changed to use `term_data[:term_type]` which is actually populated by extraction
- Now properly captures term types like 'concept', 'entity', 'place', etc.

```ruby
# Before: pool_association: term_data[:pool_type] || 'general'
# After:  pool_association: (term_data[:term_type].presence || 'general')
```

### 3. Transactional Persistence with Precise Pool-Ready Marking
**Problem:** 
- Items marked pool-ready en masse even if their terms were deduplicated away
- No transaction protection, could leave partial updates on failure

**Solution:**
- Wrapped entire `create_lexicon_entries` in a transaction
- Track `contributing_item_ids` from successfully persisted entries
- Only mark contributing items as pool-ready

```ruby
contributing_item_ids = Set.new

ApplicationRecord.transaction do
  normalized_terms.each do |term_data|
    # ... create/update lexicon entry ...
    
    # Record contributing items only after successful persistence
    (term_data[:source_item_ids] || []).each { |sid| contributing_item_ids << sid }
  end
  
  # Mark only contributing items as pool-ready
  if contributing_item_ids.any?
    @batch.ingest_items
      .where(id: contributing_item_ids.to_a)
      .where(lexicon_status: 'extracted')
      .update_all(pool_status: 'pending')
  end
end
```

## Benefits

### Data Quality
- **Accurate pool associations**: Terms now properly categorized by type instead of all being 'general'
- **Precise tracking**: Know exactly which items contributed to which lexicon entries
- **No phantom pool-ready items**: Only items that actually contributed terms are marked ready

### Reliability
- **Atomic operations**: Transaction ensures all-or-nothing persistence
- **No partial failures**: If any lexicon entry fails, no items are marked pool-ready
- **Clear audit trail**: Can trace from item → term → normalized entry

### Performance
- **Selective updates**: Only update items that actually contributed
- **Reduced database writes**: Not updating items whose terms were fully deduplicated

## Verification

All changes verified:
- ✅ Source item ID propagation working
- ✅ Term type preserved for pool association
- ✅ Transaction wrapper in place
- ✅ Selective pool-ready marking implemented

## Files Modified

1. **app/jobs/lexicon/bootstrap_job.rb**
   - Added source_item_id to extracted terms
   - Fixed pool_association to use term_type
   - Added transaction wrapper
   - Implemented selective pool-ready marking

2. **app/services/lexicon/normalization_service.rb**
   - Collect and preserve source_item_ids through merging

## Testing

```ruby
# Verify implementation
rails runner script/verify_lexicon_hardening.rb

# Test with actual data
pr = EknPipelineRun.find(37)
Lexicon::BootstrapJob.perform_now(pr.id)

# Check results
entry = LexiconAndOntology.last
entry.pool_association  # Should be term_type value, not always 'general'
entry.provenance_and_rights_id  # Should be present

# Only contributing items marked pool-ready
contributing_count = batch.ingest_items.where(pool_status: 'pending').count
contributing_count <= batch.ingest_items.where(lexicon_status: 'extracted').count
```

## Impact

This hardening ensures:
1. **No data loss**: Term types and contributing items properly tracked
2. **Better reliability**: Transaction protection prevents partial updates
3. **More precision**: Only items that contributed are advanced to next stage
4. **Improved debugging**: Can trace exactly which items contributed to which terms

The changes maintain backward compatibility while significantly improving the robustness and accuracy of Stage 3 processing.