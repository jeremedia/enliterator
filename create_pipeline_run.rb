#!/usr/bin/env ruby

# Create pipeline run and execute lexicon bootstrap
batch = IngestBatch.find(9)
ekn = batch.ekn

puts "🚀 CREATING PIPELINE RUN FOR ARCTIC RESEARCH"
puts "="*50

# Create the pipeline run  
pipeline_run = EknPipelineRun.create!(
  ekn: ekn,
  status: "running",
  current_stage: "lexicon_bootstrap", 
  pipeline_version: "2.0",
  configuration: {
    batch_ids: [batch.id],
    description: "Arctic Research MarkItDown transformation - 6.39M chars",
    target_stages: ["lexicon_bootstrap", "pool_extraction", "graph_assembly"]
  },
  metadata: {
    content_chars: batch.ingest_items.sum(:content_length_chars),
    pdf_count: 24,
    processing_method: "markitdown_enhanced"
  }
)

puts "✅ Created pipeline run #{pipeline_run.id}"
puts "   Associated with EKN: #{ekn.name}"
puts "   Content: #{pipeline_run.metadata['content_chars']} characters"

puts "\n🔄 Executing Lexicon::BootstrapJob with pipeline run #{pipeline_run.id}..."

# Execute lexicon bootstrap with proper pipeline run
time_start = Time.current
begin
  Lexicon::BootstrapJob.perform_now(pipeline_run.id)
  time_taken = (Time.current - time_start).round(2)
  puts "✅ Lexicon bootstrap complete in #{time_taken} seconds!"
rescue => e
  puts "❌ Error during lexicon bootstrap: #{e.message}"
  puts "   #{e.backtrace.first(3).join("\n   ")}"
end

# Check results
pipeline_run.reload
puts "\n📊 Results:"
puts "   Pipeline run status: #{pipeline_run.status}"
puts "   Current stage: #{pipeline_run.current_stage}"

# Check item processing
processed_count = batch.ingest_items.where(lexicon_status: "completed").count
puts "   Items processed: #{processed_count}/#{batch.ingest_items.count}"

# Check lexicon entries created
lexicon_count = LexiconAndOntology.count
puts "   Lexicon entries: #{lexicon_count}"