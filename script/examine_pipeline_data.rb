#!/usr/bin/env ruby
# Examine existing pipeline data from processing Enliterator codebase

require_relative '../config/environment'

puts "\n" + "="*80
puts "Examining Pipeline Data (Meta-Enliterator)"
puts "="*80

# Check IngestBatch records
puts "\n1. IngestBatch Records:"
puts "-" * 40
IngestBatch.find_each do |batch|
  puts "\nBatch ##{batch.id}: #{batch.name}"
  puts "  Status: #{batch.status}"
  puts "  Source Type: #{batch.source_type}"
  puts "  Created: #{batch.created_at}"
  puts "  Graph Assembled: #{batch.graph_assembled_at}"
  puts "  Deliverables Generated: #{batch.deliverables_generated_at}"
  puts "  Deliverables Path: #{batch.deliverables_path}"
  puts "  Items Count: #{batch.ingest_items.count}"
  puts "  Literacy Score: #{batch.literacy_score}"
  
  if batch.statistics.present?
    puts "  Statistics:"
    batch.statistics.each do |key, value|
      puts "    #{key}: #{value}"
    end
  end
  
  if batch.graph_assembly_stats.present?
    puts "  Graph Assembly Stats:"
    batch.graph_assembly_stats.each do |key, value|
      puts "    #{key}: #{value}"
    end
  end
end

# Check IngestItems for most recent batch
latest_batch = IngestBatch.order(created_at: :desc).first
if latest_batch
  puts "\n2. IngestItems for Latest Batch (#{latest_batch.name}):"
  puts "-" * 40
  
  by_status = latest_batch.ingest_items.group(:triage_status).count
  puts "  By Triage Status:"
  by_status.each do |status, count|
    puts "    #{status}: #{count}"
  end
  
  # Check if mime_type column exists
  if latest_batch.ingest_items.column_names.include?('mime_type')
    by_type = latest_batch.ingest_items.group(:mime_type).count
    puts "  By MIME Type (top 5):"
    by_type.sort_by { |_, v| -v }.first(5).each do |type, count|
      puts "    #{type}: #{count}"
    end
  end
  
  # Sample items
  puts "  Sample Items:"
  latest_batch.ingest_items.limit(5).each do |item|
    puts "    - #{item.file_path} (#{item.triage_status})"
  end
end

# Check Lexicon data
puts "\n3. Lexicon Data:"
puts "-" * 40
total_lexicon = LexiconEntry.count
puts "  Total Lexicon Entries: #{total_lexicon}"
if total_lexicon > 0
  by_pool = LexiconEntry.group(:pool).count
  puts "  By Pool:"
  by_pool.each do |pool, count|
    puts "    #{pool}: #{count}"
  end
  
  puts "  Sample Entries:"
  LexiconEntry.limit(5).each do |entry|
    puts "    - #{entry.canonical_name} (#{entry.pool})"
  end
end

# Check Pool models
puts "\n4. Pool Entities:"
puts "-" * 40
[IdeaPool, ManifestPool, ExperiencePool, RelationalPool, EvolutionaryPool, 
 PracticalPool, EmanationPool].each do |pool_class|
  count = pool_class.count
  if count > 0
    puts "  #{pool_class.name}: #{count}"
    # Sample
    sample = pool_class.first
    if sample
      puts "    Sample: #{sample.name || sample.title || sample.description&.truncate(50)}"
    end
  end
end

# Check Embeddings
puts "\n5. Embeddings:"
puts "-" * 40
total_embeddings = Embedding.count
puts "  Total Embeddings: #{total_embeddings}"
if total_embeddings > 0
  by_type = Embedding.group(:entity_type).count
  puts "  By Entity Type:"
  by_type.each do |type, count|
    puts "    #{type}: #{count}"
  end
end

# Check Neo4j Graph (default database)
puts "\n6. Neo4j Graph (default database):"
puts "-" * 40
begin
  driver = Graph::Connection.instance.driver
  session = driver.session # Uses default 'neo4j' database
  
  # Count nodes by label
  result = session.run(<<~CYPHER)
    MATCH (n)
    RETURN labels(n)[0] as label, count(n) as count
    ORDER BY count DESC
    LIMIT 10
  CYPHER
  
  puts "  Node Counts by Label:"
  result.each do |record|
    puts "    #{record['label']}: #{record['count']}"
  end
  
  # Count relationships
  result = session.run("MATCH ()-[r]->() RETURN count(r) as count")
  rel_count = result.single['count']
  puts "  Total Relationships: #{rel_count}"
  
  # Sample nodes with name
  result = session.run(<<~CYPHER)
    MATCH (n)
    WHERE n.name IS NOT NULL
    RETURN labels(n)[0] as label, n.name as name
    LIMIT 5
  CYPHER
  
  puts "  Sample Nodes:"
  result.each do |record|
    puts "    #{record['label']}: #{record['name']}"
  end
  
  session.close
rescue => e
  puts "  Error accessing Neo4j: #{e.message}"
end

# Check deliverables
puts "\n7. Generated Deliverables:"
puts "-" * 40
if latest_batch&.deliverables_path
  path = latest_batch.deliverables_path
  if File.exist?(path)
    puts "  Path: #{path}"
    Dir.glob("#{path}/*").each do |file|
      size = File.size(file) / 1024.0
      puts "    - #{File.basename(file)} (#{size.round(1)} KB)"
    end
  else
    puts "  Deliverables path doesn't exist: #{path}"
  end
end

# Check FineTuneJobs
puts "\n8. Fine-Tune Jobs:"
puts "-" * 40
FineTuneJob.find_each do |job|
  puts "  Job ##{job.id}:"
  puts "    Batch: #{job.ingest_batch&.name}"
  puts "    Status: #{job.status}"
  puts "    OpenAI Job ID: #{job.openai_job_id}"
  puts "    Model: #{job.fine_tuned_model}"
  puts "    Created: #{job.created_at}"
end

puts "\n" + "="*80
puts "Summary:"
puts "="*80
puts "This is the META-ENLITERATOR data - Enliterator analyzing itself!"
puts "The pipeline has processed the Enliterator codebase and created:"
puts "  - Lexicon entries for code concepts"
puts "  - Pool entities extracted from the codebase"
puts "  - Knowledge graph in Neo4j"
puts "  - Embeddings for semantic search"
puts "  - Fine-tuned model for navigation"
puts "\nTo create an isolated EKN for this data:"
puts "  1. Create a new EKN: ekn = EknManager.create_ekn(name: 'Meta-Enliterator')"
puts "  2. Migrate the data from default database to ekn-{id}"
puts "  3. Update Navigator to use the isolated EKN"
puts "="*80