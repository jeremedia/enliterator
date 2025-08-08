# Stage 1: Intake - Detailed Documentation

## Overview
Stage 1 (Intake) is the entry point to the pipeline, responsible for processing raw files and preparing them for rights triage. This stage reads file content, calculates hashes for deduplication, detects media types, and populates the content fields required by downstream stages.

## Job Implementation
**File**: `/app/jobs/pipeline/intake_job.rb`
**Queue**: `:intake`
**Base Class**: `Pipeline::BaseJob`

## Input Requirements

### IngestBatch
- Must exist with associated IngestItems
- Each IngestItem must have:
  - `file_path`: Valid path to a file on the filesystem
  - `ingest_batch_id`: Association to the batch

### File System
- Files referenced by `file_path` should be readable
- Files can be of any type (text, code, config, data, etc.)

## Processing Logic

### Main Flow
```ruby
def perform(pipeline_run_id)
  @batch.ingest_items.find_each do |item|
    begin
      process_item(item)
      processed += 1
    rescue => e
      log_progress "Failed to process item #{item.id}: #{e.message}", level: :warn
      failed += 1
      item.update!(triage_status: 'failed', triage_error: e.message)
    end
  end
end
```

### Item Processing
```ruby
def process_item(item)
  # Step 1: Detect media type
  if item.media_type.blank? || item.media_type == 'unknown'
    item.media_type = detect_media_type(item.file_path)
  end
  
  # Step 2: Calculate file hash for deduplication
  if item.file_hash.blank? && File.exist?(item.file_path)
    item.file_hash = calculate_file_hash(item.file_path)
  end
  
  # Step 3: Read file content
  if File.exist?(item.file_path)
    item.file_size = File.size(item.file_path)
    
    full_content = File.read(item.file_path, encoding: 'UTF-8', invalid: :replace, undef: :replace)
    item.content_sample = full_content[0..4999]  # First 5000 chars for rights inference
    item.content = full_content  # CRITICAL: Full content for processing
  end
  
  # Step 4: Mark as pending for rights triage
  item.triage_status = 'pending'
  item.save!
end
```

### Media Type Detection
The stage uses sophisticated pattern matching to determine media types:

```ruby
def detect_media_type(file_path)
  extension = File.extname(file_path).downcase
  basename = File.basename(file_path).downcase
  
  # Config file patterns (checked first)
  if basename.match?(/^(gemfile|rakefile|dockerfile|makefile)/)
    return 'config'
  end
  
  # Extension-based detection
  case extension
  when '.rb', '.py', '.js', '.ts', '.java', '.go'
    'code'
  when '.md', '.txt', '.rst'
    'text'
  when '.yml', '.yaml', '.toml', '.ini'
    'config'
  when '.json', '.xml', '.csv'
    'data'
  when '.pdf', '.doc', '.docx'
    'document'
  when '.jpg', '.png', '.gif'
    'image'
  when '.mp3', '.wav'
    'audio'
  when '.mp4', '.avi'
    'video'
  else
    'unknown'
  end
end
```

## Output Data

### IngestItem Updates
Each successfully processed item will have:

```ruby
{
  media_type: 'text',           # Detected type (enum)
  file_hash: 'abc123...',       # SHA256 hash
  file_size: 1024,              # Size in bytes
  content: 'Full file content', # CRITICAL: Required by later stages
  content_sample: 'First 5000', # For rights inference
  triage_status: 'pending'      # Ready for Stage 2
}
```

### Failed Items
Items that fail processing will have:

```ruby
{
  triage_status: 'failed',
  triage_error: 'Error message'
}
```

### Batch Status
The batch is updated to:
```ruby
status: 'intake_completed'
```

## Metrics Tracked

```ruby
{
  items_processed: 10,  # Successfully processed
  items_failed: 0,      # Failed with errors
  total_items: 10,      # Total in batch
  batch_id: 123
}
```

## Error Handling

### File Read Errors
- If file cannot be read, sets empty content but continues
- Logs warning but doesn't fail the item
- Item still advances to rights triage

### Missing Files
- If file doesn't exist, hash and size are skipped
- Content fields set to empty strings
- Item still marked pending for triage

### Encoding Issues
- Uses UTF-8 with invalid/undefined character replacement
- Prevents encoding errors from failing the pipeline
- Ensures content is always readable by downstream stages

## Critical Fields

### MUST be set for downstream stages:
1. **`content`**: Full file content (NOT `extracted_text`)
   - Required by Stage 3 (Lexicon) for term extraction
   - Required by Stage 4 (Pools) for entity extraction
   
2. **`content_sample`**: First 5000 characters
   - Used by Stage 2 (Rights) for inference
   
3. **`triage_status`**: Must be 'pending'
   - Stage 2 only processes items with this status

## Common Issues

### Issue 1: Content Field Not Set
**Symptom**: Later stages fail with "content is blank"
**Cause**: Using wrong field name (e.g., `extracted_text`)
**Solution**: Ensure setting `item.content = full_content`

### Issue 2: Large Files
**Symptom**: Memory issues or timeouts
**Cause**: Reading entire file into memory
**Current Behavior**: No size limit, reads entire file
**Potential Solution**: Stream large files or set size limits

### Issue 3: Binary Files
**Symptom**: Encoding errors or garbage content
**Cause**: Trying to read binary as text
**Current Behavior**: Replaces invalid characters
**Note**: Binary files marked but content still read

## Performance Characteristics

### Timing
- File read: ~1-10ms per file (depends on size)
- Hash calculation: ~5-20ms per file
- Media type detection: <1ms (pattern matching)
- Database updates: ~5-10ms per item

### Typical Performance
- 10 items: ~5 seconds
- 100 items: ~30 seconds
- 1000 items: ~5 minutes

### Bottlenecks
1. File I/O for large files
2. Sequential processing (no parallelization)
3. Individual database updates (not batched)

## Testing Recommendations

### Unit Tests
```ruby
# Test media type detection
assert_equal 'code', detect_media_type('app.rb')
assert_equal 'config', detect_media_type('Gemfile')
assert_equal 'text', detect_media_type('README.md')

# Test content reading
item = create(:ingest_item, file_path: 'test.txt')
IntakeJob.new.process_item(item)
assert_equal 'file content', item.content
assert_equal 'file ', item.content_sample
```

### Integration Tests
```ruby
# Test full pipeline flow
batch = create(:ingest_batch)
create_list(:ingest_item, 10, ingest_batch: batch)

IntakeJob.perform_now(pipeline_run.id)

assert_equal 'intake_completed', batch.reload.status
assert_equal 10, batch.ingest_items.where(triage_status: 'pending').count
```

## Next Stage
Items with `triage_status: 'pending'` proceed to Stage 2 (Rights & Provenance) for rights inference and attribution.