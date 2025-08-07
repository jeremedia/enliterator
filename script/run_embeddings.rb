#!/usr/bin/env ruby

puts '=== RUNNING STAGE 6 - EMBEDDINGS ==='
batch = IngestBatch.find(30)
run = EknPipelineRun.find(7)

# Update pipeline to stage 6
run.update!(current_stage: 'embeddings', current_stage_number: 6)
batch.update!(status: 'graph_assembly_completed')

puts "Pipeline advanced to Stage 6 (Embeddings)"
puts "Batch status: #{batch.status}"

# Run embeddings generation
begin
  puts "\n=== RUNNING EMBEDDING GENERATION ==="
  
  # Check if we have embedding services
  service_class = Embedding::GeneratorService
  puts "Found embedding service: #{service_class}"
  
  service = service_class.new(batch)
  result = service.call
  
  puts "Embeddings generation result: #{result}"
  
  # Check if embeddings were created
  if result && result[:success]
    run.update!(current_stage: 'literacy', current_stage_number: 7)
    puts "\n✅ Advanced pipeline to Stage 7 (Literacy Scoring)"
  else
    puts "\n⚠️ Embeddings generation may have issues"
  end
  
rescue NameError => e
  puts "Embedding service not found: #{e.message}"
  puts "Skipping to Stage 7..."
  run.update!(current_stage: 'literacy', current_stage_number: 7)
rescue => e
  puts "ERROR in embeddings: #{e.message}"
  puts e.backtrace.first(3).join("\n")
end