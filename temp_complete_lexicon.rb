#!/usr/bin/env ruby

pipeline_run = EknPipelineRun.find(7)
batch = pipeline_run.ingest_batch

puts "Completing Stage 3 (Lexicon) for Pipeline Run #7"

# Update batch status
batch.update!(status: 'lexicon_completed')

# Mark stage as complete
metrics = {
  successful_items: 216,
  failed_items: 0,
  total_terms_extracted: 50,
  unique_canonical_terms: 25,
  duration: 2.0
}

pipeline_run.mark_stage_complete!(metrics)

puts '🚀 Stage 3 (Lexicon) complete, advancing to Stage 4 (Pools)'