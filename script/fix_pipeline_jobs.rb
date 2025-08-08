# Script to fix all pipeline jobs to follow correct patterns
# Run with: rails runner script/fix_pipeline_jobs.rb

puts "=" * 80
puts "PIPELINE JOB FIX REPORT"
puts "=" * 80

# List all jobs that need fixing
jobs_to_fix = {
  "Lexicon::BootstrapJob" => "Stage 3",
  "Pools::ExtractionJob" => "Stage 4", 
  "Graph::AssemblyJob" => "Stage 5",
  "Embedding::BuilderJob" => "Stage 6",
  "Embedding::Neo4jBuilderJob" => "Stage 6",
  "Literacy::ScoringJob" => "Stage 7",
  "Deliverables::GenerationJob" => "Stage 8",
  "FineTune::DatasetBuilderJob" => "Stage 9"
}

# Check which jobs exist
existing_jobs = []
missing_jobs = []

jobs_to_fix.each do |job_class, stage|
  begin
    job_class.constantize
    existing_jobs << [job_class, stage]
  rescue NameError
    missing_jobs << [job_class, stage]
  end
end

puts "\n✅ Existing Jobs (need fixing):"
existing_jobs.each do |job_class, stage|
  puts "   - #{job_class} (#{stage})"
end

puts "\n❌ Missing Jobs:"
missing_jobs.each do |job_class, stage|
  puts "   - #{job_class} (#{stage})"
end

# Check for missing IngestItem fields
puts "\n📋 IngestItem Fields Check:"
required_fields = %w[
  triage_status triage_error
  lexicon_status lexicon_metadata
  pool_status pool_metadata
  graph_status graph_metadata
  embedding_status embedding_metadata
]

existing_fields = IngestItem.column_names
missing_fields = required_fields - existing_fields

puts "   Existing: #{(required_fields & existing_fields).join(', ')}"
puts "   Missing: #{missing_fields.join(', ')}"

# Check for missing service classes
puts "\n🔧 Required Service Classes:"
required_services = [
  "Rights::InferenceService",
  "Lexicon::TermExtractionService", 
  "Lexicon::NormalizationService",
  "Pools::EntityExtractionService",
  "Pools::RelationExtractionService",
  "Graph::SchemaManager",
  "Graph::NodeLoader",
  "Graph::EdgeLoader",
  "Graph::Deduplicator",
  "Graph::OrphanRemover",
  "Graph::IntegrityVerifier"
]

required_services.each do |service|
  exists = begin
    service.constantize
    true
  rescue NameError
    false
  end
  
  status = exists ? "✅" : "❌"
  puts "   #{status} #{service}"
end

puts "\n" + "=" * 80
puts "RECOMMENDATIONS:"
puts "=" * 80

puts """
1. Add missing fields to IngestItem via migration:
   - #{missing_fields.join(', ')}

2. Create stub service classes with basic implementation

3. Fix job inheritance pattern:
   - All pipeline jobs should inherit from Pipeline::BaseJob
   - Use perform(pipeline_run_id) signature
   - Do NOT call super in perform method

4. Implement collect_stage_metrics in each job

5. Use BaseJob helper methods:
   - log_progress for logging
   - track_metric for metrics
   - items_to_process for getting items
"""

puts "\n" + "=" * 80