# Pipeline Error Fix Plan

## Current State
- Micro test (10 files) completed Stages 1-4 successfully
- Stage 5 (Graph) fails with state transition error
- GPT-5 integration working after fixes
- Multiple architectural issues identified

## Priority 1: Fix AASM State Transition Errors

### Root Cause
- Jobs trying to transition pipeline from 'failed' to 'failed'
- Race condition when multiple jobs fail simultaneously
- Error handling in Pipeline::BaseJob doesn't check current state

### Solution
```ruby
# app/models/ekn_pipeline_run.rb
def mark_stage_failed!(error_message)
  return if failed? # Already failed, don't transition
  
  with_lock do
    fail! if can_fail?
    update!(error_message: error_message)
  end
rescue AASM::InvalidTransition => e
  # Already in failed state, just update error message
  update_column(:error_message, error_message)
end
```

### Action Items
1. Audit all state transitions in EknPipelineRun
2. Add guards to prevent invalid transitions
3. Use database locks for concurrent access
4. Add idempotent error handling

## Priority 2: Fix Graph::AssemblyJob

### Potential Issues
1. Neo4j connection/database creation
2. Empty or malformed entity/relation data
3. Missing required fields
4. Graph schema conflicts

### Debugging Steps
```ruby
# Add comprehensive logging
class Graph::AssemblyJob < Pipeline::BaseJob
  def perform_stage(pipeline_run_id)
    log_progress "Starting Graph Assembly..."
    
    # Verify data exists
    entities = load_entities
    log_progress "Loaded #{entities.count} entities"
    
    relations = load_relations
    log_progress "Loaded #{relations.count} relations"
    
    # Verify Neo4j connection
    verify_neo4j_connection!
    
    # Create/switch database
    ensure_database_exists!
    
    # Load with error handling
    load_nodes_with_retry(entities)
    load_edges_with_retry(relations)
  end
end
```

### Action Items
1. Add detailed logging at each step
2. Validate data before processing
3. Implement retry logic for Neo4j operations
4. Handle partial failures gracefully

## Priority 3: Pipeline Resilience

### Current Problems
- All-or-nothing processing
- No retry mechanism
- Poor error isolation
- Manual intervention required

### Proposed Architecture
```
Pipeline Run
  ├── Stage 1: Intake
  │   ├── Retry: 3 times
  │   ├── Skip failed items: Yes
  │   └── Continue on error: Yes
  ├── Stage 2: Rights
  │   ├── Retry: 2 times
  │   ├── Quarantine unknowns: Yes
  │   └── Continue on error: Yes
  └── Stage N: ...
      ├── Checkpoint after completion
      ├── Resume from checkpoint
      └── Manual override available
```

### Implementation
```ruby
# app/jobs/pipeline/base_job.rb
class Pipeline::BaseJob < ApplicationJob
  retry_on StandardError, wait: :exponentially_longer, attempts: 3
  
  def perform(pipeline_run_id)
    @pipeline_run = EknPipelineRun.find(pipeline_run_id)
    
    return if should_skip_stage?
    
    with_error_handling do
      perform_stage(pipeline_run_id)
      mark_stage_complete!
    end
  end
  
  private
  
  def with_error_handling
    yield
  rescue => e
    if retriable_error?(e)
      raise # Let retry_on handle it
    else
      handle_permanent_failure(e)
    end
  end
  
  def handle_permanent_failure(error)
    if @pipeline_run.continue_on_error?
      log_error_and_continue(error)
    else
      mark_stage_failed!(error)
    end
  end
end
```

## Priority 4: Monitoring & Debugging

### Add Pipeline Dashboard
```ruby
# app/controllers/admin/pipeline_monitor_controller.rb
class Admin::PipelineMonitorController < Admin::BaseController
  def show
    @pipeline_run = EknPipelineRun.find(params[:id])
    @stage_stats = @pipeline_run.stage_statistics
    @failed_items = @pipeline_run.failed_items
    @performance_metrics = @pipeline_run.performance_metrics
  end
  
  def retry_stage
    @pipeline_run = EknPipelineRun.find(params[:id])
    @pipeline_run.retry_current_stage!
    redirect_to admin_pipeline_monitor_path(@pipeline_run)
  end
  
  def skip_stage
    @pipeline_run = EknPipelineRun.find(params[:id])
    @pipeline_run.skip_to_next_stage!
    redirect_to admin_pipeline_monitor_path(@pipeline_run)
  end
end
```

### Add Comprehensive Logging
```ruby
# config/initializers/pipeline_logging.rb
Rails.application.configure do
  config.pipeline_logger = ActiveSupport::Logger.new(
    Rails.root.join('log', 'pipeline.log')
  )
  config.pipeline_logger.level = Logger::DEBUG
end

# Use structured logging
def log_pipeline_event(event_type, data = {})
  Rails.configuration.pipeline_logger.info({
    timestamp: Time.current.iso8601,
    event: event_type,
    pipeline_run_id: @pipeline_run&.id,
    stage: @pipeline_run&.current_stage,
    **data
  }.to_json)
end
```

## Priority 5: Quick Wins

### 1. Add Stage Skip Capability
```ruby
# For development/testing
rails runner 'EknPipelineRun.find(37).skip_to_stage!(6)'
```

### 2. Add Force Complete
```ruby
# Mark stage as complete despite failures
rails runner 'EknPipelineRun.find(37).force_complete_stage!'
```

### 3. Add Pipeline Reset
```ruby
# Reset to specific stage for retry
rails runner 'EknPipelineRun.find(37).reset_to_stage!(4)'
```

## Implementation Order

### Phase 1: Immediate Fixes (Today)
1. Fix state transition guards
2. Add basic retry logic
3. Fix Graph::AssemblyJob initialization
4. Add skip/force commands for testing

### Phase 2: Resilience (Tomorrow)
1. Implement proper retry_on in all jobs
2. Add continue_on_error option
3. Create checkpoint system
4. Add item-level error isolation

### Phase 3: Monitoring (Later)
1. Build admin dashboard
2. Add structured logging
3. Create alerting system
4. Add performance metrics

## Testing Strategy

### 1. Unit Tests
- Test state transitions with concurrent access
- Test retry logic with various failure types
- Test data validation in each stage

### 2. Integration Tests
- Test full pipeline with deliberate failures
- Test recovery from partial completion
- Test checkpoint/resume functionality

### 3. Load Tests
- Test with full 266 files
- Test with concurrent pipelines
- Test Neo4j performance with large datasets

## Success Criteria
- [ ] Pipeline completes all 9 stages without manual intervention
- [ ] Failed items don't stop entire pipeline
- [ ] State transitions never raise AASM errors
- [ ] Graph stage successfully loads data to Neo4j
- [ ] Pipeline can be resumed from any checkpoint
- [ ] Full 266-file batch processes in < 30 minutes with GPT-5

## Next Immediate Actions
1. Fix state transition guards in EknPipelineRun
2. Debug Graph::AssemblyJob with detailed logging
3. Add retry_on to Pipeline::BaseJob
4. Test micro pipeline with fixes
5. Run full 266-file pipeline test