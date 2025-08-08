#!/usr/bin/env ruby
# Test script for embedding integration with Neo4j GenAI

puts "Testing Embedding Integration with Neo4j GenAI..."
puts "="*50

# Check if we have OpenAI API key
has_api_key = ENV['OPENAI_API_KEY'].present?
puts "OpenAI API key: #{has_api_key ? 'SET' : 'NOT SET'}"

# Try to configure Neo4j GenAI provider
begin
  database_name = "neo4j"
  vector_service = Neo4j::VectorIndexService.new(database_name)
  
  puts "\nAttempting to configure Neo4j GenAI provider..."
  if vector_service.configure_provider
    puts "✅ Neo4j GenAI provider configured successfully"
    provider_available = true
  else
    puts "⚠️  Neo4j GenAI provider configuration failed"
    provider_available = false
  end
rescue => e
  puts "❌ Error configuring provider: #{e.message}"
  provider_available = false
end

# Create a test pipeline run to test the job
ekn = Ekn.first || Ekn.create!(
  name: "Test EKN",
  description: "Test EKN for embedding validation"
)

batch = IngestBatch.create!(
  name: "test_embedding_batch",
  source_type: "test",
  ekn_id: ekn.id,
  status: "graph_assembly_completed"
)

# Create some test items
3.times do |i|
  item = batch.ingest_items.create!(
    file_path: "/tmp/test_#{i}.txt",
    media_type: "text",
    graph_status: "assembled",
    embedding_status: "pending",
    training_eligible: true
  )
end

pipeline_run = EknPipelineRun.create!(
  ekn_id: ekn.id,
  ingest_batch_id: batch.id,
  status: "running",
  current_stage: 6
)

puts "\nRunning RepresentationJob..."
begin
  Embedding::RepresentationJob.perform_now(pipeline_run.id)
  
  # Check results
  batch.reload
  items_with_embeddings = batch.ingest_items.where(embedding_status: "embedded").count
  fallback_used = batch.metadata["embeddings_fallback_used"] == true
  
  puts "\nResults:"
  puts "  Batch status: #{batch.status}"
  puts "  Items with embeddings: #{items_with_embeddings}/#{batch.ingest_items.count}"
  puts "  Fallback used: #{fallback_used}"
  
  if fallback_used
    puts "  ⚠️  Fallback embedding strategy was used (Neo4j GenAI unavailable)"
  elsif items_with_embeddings > 0
    puts "  ✅ Real embeddings were generated using Neo4j GenAI"
  else
    puts "  ❌ No embeddings were created"
  end
  
rescue => e
  puts "❌ Error running RepresentationJob: #{e.message}"
  puts e.backtrace.first(5).join("\n")
end

# Cleanup
pipeline_run&.destroy
batch&.destroy

puts "\n✅ Test complete!"