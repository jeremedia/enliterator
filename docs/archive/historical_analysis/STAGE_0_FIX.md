# Stage 0 (Frame) Status Fix

## Problem
Stage 0 was displaying as "Initialized - Pipeline created, ready to start" in the UI and never showed as completed, even after the pipeline had progressed through multiple stages.

## Root Cause
Stage 0 represents the initial "Frame the Mission" stage where configuration and goal setting occur. However, it wasn't being marked as completed when the pipeline transitioned from `initialized` to `running` state. This was because:

1. Stage 0 has no associated job (`job: nil` in PIPELINE_STAGES)
2. It's just the initial state, not an actual processing stage
3. The `start!` event didn't update the stage_statuses hash

## Solution

### 1. Updated the `start` event in EknPipelineRun
```ruby
event :start do
  transitions from: [:initialized, :paused, :failed], to: :running
  after do
    update!(started_at: Time.current) if started_at.nil?
    
    # Mark Stage 0 (initialized/frame) as completed since we're starting
    stage_statuses['initialized'] = 'completed'
    save!
    
    log_info("🚀 PIPELINE STARTED for EKN: #{ekn.name}", label: "pipeline")
    advance_to_next_stage!
  end
end
```

### 2. Updated Stage 0 description
Changed from: `'Pipeline created, ready to start'`
To: `'Frame the mission - Configuration and goal setting'`

This better reflects that Stage 0 is the "Frame" stage from the 9-stage pipeline specification.

## Impact
- ✅ Stage 0 now shows as completed (✅) once pipeline starts
- ✅ UI correctly reflects all 10 stages (0-9) with proper status indicators
- ✅ Retroactively fixed 9 existing pipelines
- ✅ New pipelines automatically handle Stage 0 correctly

## Testing
Created test script that verifies:
1. New pipelines mark Stage 0 as completed when started
2. Existing pipelines can be retroactively fixed
3. Stage statuses properly persist to database

## Files Modified
- `/app/models/ekn_pipeline_run.rb` - Updated start event and PIPELINE_STAGES constant
- `/script/test_stage_0_fix.rb` - Test script to verify fix
- `/script/fix_existing_stage_0.rb` - Script to fix existing pipelines

## Result
Stage 0 now properly displays as completed in the pipeline detail view, providing users with accurate visual feedback about pipeline progress through all stages.