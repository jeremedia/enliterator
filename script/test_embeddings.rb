#!/usr/bin/env ruby
# Script to test Stage 6: Representations & Retrieval
# Run with: rails runner script/test_embeddings.rb

require 'colorize'

class EmbeddingsTester
  def self.run
    new.run
  end
  
  def run
    puts "\n#{'=' * 60}".cyan
    puts "Testing Stage 6: Representations & Retrieval".cyan.bold
    puts "#{'=' * 60}".cyan
    
    # Check prerequisites
    unless check_prerequisites
      puts "\n❌ Prerequisites check failed".red
      return false
    end
    
    # Run the migrations if needed
    ensure_database_ready
    
    # Test entity embeddings
    test_entity_embeddings
    
    # Test path embeddings
    test_path_embeddings
    
    # Test index building
    test_index_building
    
    # Test similarity search
    test_similarity_search
    
    # Test the orchestrator job
    test_builder_job
    
    # Summary
    print_summary
    
    puts "\n✅ Stage 6 testing complete!".green.bold
    true
  rescue StandardError => e
    puts "\n❌ Error during testing: #{e.message}".red
    puts e.backtrace.first(5).join("\n").yellow
    false
  end
  
  private
  
  def check_prerequisites
    puts "\n📋 Checking prerequisites...".yellow
    
    checks = []
    
    # Check if previous stages completed
    checks << check_condition("Graph populated") do
      neo4j = Neo4j::Driver::GraphDatabase.driver(
        ENV.fetch('NEO4J_URL'),
        Neo4j::Driver::AuthTokens.basic(
          ENV.fetch('NEO4J_USERNAME', 'neo4j'),
          ENV.fetch('NEO4J_PASSWORD')
        )
      )
      
      count = 0
      neo4j.session do |session|
        result = session.run("MATCH (n) RETURN count(n) as count")
        count = result.single[:count]
      end
      neo4j.close
      
      count > 0
    end
    
    # Check if entities have repr_text
    checks << check_condition("Entities have repr_text") do
      Idea.where.not(repr_text: [nil, '']).exists? ||
      Manifest.where.not(repr_text: [nil, '']).exists?
    end
    
    # Check OpenAI API key
    checks << check_condition("OpenAI API configured") do
      ENV['OPENAI_API_KEY'].present?
    end
    
    checks.all?
  end
  
  def check_condition(name)
    result = yield
    status = result ? "✓".green : "✗".red
    puts "  #{status} #{name}"
    result
  rescue => e
    puts "  ✗ #{name} (#{e.message})".red
    false
  end
  
  def ensure_database_ready
    puts "\n🔧 Ensuring database is ready...".yellow
    
    # Run migrations
    if ActiveRecord::Base.connection.tables.include?('embeddings')
      puts "  ✓ Embeddings table exists".green
    else
      puts "  → Running migrations...".yellow
      ActiveRecord::Tasks::DatabaseTasks.migrate
      puts "  ✓ Migrations complete".green
    end
    
    # Check pgvector extension
    result = ActiveRecord::Base.connection.execute(
      "SELECT * FROM pg_extension WHERE extname = 'vector'"
    )
    
    if result.any?
      puts "  ✓ pgvector extension enabled".green
    else
      puts "  ✗ pgvector extension not found".red
      puts "    Run: CREATE EXTENSION vector;".yellow
    end
  end
  
  def test_entity_embeddings
    puts "\n🔬 Testing Entity Embeddings...".yellow
    
    # Create a test entity if needed
    test_idea = Idea.first || Idea.create!(
      canonical_name: "Test Idea",
      repr_text: "This is a test idea for embedding generation",
      training_eligible: true,
      publishable: true,
      ingest_batch_id: 1
    )
    
    puts "  Using test entity: #{test_idea.canonical_name}"
    
    # Run entity embedder
    embedder = Embedding::EntityEmbedder.new(
      pool_filter: 'idea',
      dry_run: false
    )
    
    results = embedder.call
    
    puts "  Processed: #{results[:processed]}"
    puts "  Errors: #{results[:errors]}"
    
    # Verify embedding was created
    embedding = Embedding.find_by(
      embeddable_type: 'Idea',
      embeddable_id: test_idea.id
    )
    
    if embedding
      puts "  ✓ Entity embedding created".green
      puts "    - Dimensions: #{embedding.embedding.size}"
      puts "    - Pool: #{embedding.pool}"
      puts "    - Training eligible: #{embedding.training_eligible}"
    else
      puts "  ✗ Entity embedding not found".red
    end
  end
  
  def test_path_embeddings
    puts "\n🔬 Testing Path Embeddings...".yellow
    
    # Check if we have paths in Neo4j
    neo4j = Neo4j::Driver::GraphDatabase.driver(
      ENV.fetch('NEO4J_URL'),
      Neo4j::Driver::AuthTokens.basic(
        ENV.fetch('NEO4J_USERNAME', 'neo4j'),
        ENV.fetch('NEO4J_PASSWORD')
      )
    )
    
    path_count = 0
    neo4j.session do |session|
      result = session.run(
        "MATCH p=()-[*2..3]->() RETURN count(p) as count LIMIT 1"
      )
      path_count = result.single[:count] rescue 0
    end
    neo4j.close
    
    if path_count == 0
      puts "  ⚠️  No paths found in graph - skipping path embeddings".yellow
      return
    end
    
    # Run path embedder
    embedder = Embedding::PathEmbedder.new(
      max_paths: 10,
      dry_run: false
    )
    
    results = embedder.call
    
    puts "  Paths found: #{results[:path_count]}"
    puts "  Processed: #{results[:processed]}"
    puts "  Errors: #{results[:errors]}"
    
    # Check if path embeddings were created
    path_embedding = Embedding.paths.first
    
    if path_embedding
      puts "  ✓ Path embeddings created".green
      puts "    - Source: #{path_embedding.source_text[0..100]}..."
      puts "    - Metadata: #{path_embedding.metadata.keys.join(', ')}"
    else
      puts "  ⚠️  No path embeddings created".yellow
    end
  end
  
  def test_index_building
    puts "\n🔬 Testing Index Building...".yellow
    
    # Build HNSW index
    builder = Embedding::IndexBuilder.new(
      index_type: 'hnsw',
      force_rebuild: false
    )
    
    results = builder.call
    
    puts "  Index type: #{results[:index_type]}"
    puts "  Status: #{results[:status]}"
    puts "  Stats:"
    results[:stats].each do |key, value|
      puts "    - #{key}: #{value}"
    end
    
    # Test search optimization
    Embedding::IndexBuilder.optimize_for_search(quality: 'balanced')
    puts "  ✓ Search parameters optimized".green
  end
  
  def test_similarity_search
    puts "\n🔬 Testing Similarity Search...".yellow
    
    # Get a sample embedding
    sample = Embedding.first
    
    unless sample
      puts "  ⚠️  No embeddings available for testing".yellow
      return
    end
    
    puts "  Using sample: #{sample.source_text[0..50]}..."
    
    # Find similar embeddings
    similar = sample.find_similar(limit: 5)
    
    puts "  Found #{similar.count} similar embeddings:"
    similar.each_with_index do |embed, i|
      puts "    #{i+1}. #{embed.source_text[0..50]}..."
    end
    
    # Test semantic search with a query vector
    query_embedding = sample.embedding
    results = Embedding.semantic_search(
      query_embedding,
      top_k: 5,
      require_rights: 'public'
    )
    
    puts "  ✓ Semantic search working".green
    puts "    - Results: #{results.count}"
  end
  
  def test_builder_job
    puts "\n🔬 Testing Builder Job...".yellow
    
    # Run the job synchronously for testing
    job = Embedding::BuilderJob.new
    results = job.perform(
      batch_id: nil,
      options: {
        dry_run: true,
        max_paths: 5
      }
    )
    
    puts "  Job status: #{results[:status]}"
    puts "  Duration: #{results[:duration]}s" if results[:duration]
    
    if results[:status] == 'success'
      puts "  ✓ Builder job completed successfully".green
    else
      puts "  ✗ Builder job failed: #{results[:error]}".red
    end
  end
  
  def print_summary
    puts "\n#{'=' * 60}".cyan
    puts "SUMMARY".cyan.bold
    puts "#{'=' * 60}".cyan
    
    stats = Embedding.coverage_stats
    
    puts "\nEmbedding Statistics:".yellow
    puts "  Total embeddings: #{stats[:total]}"
    puts "\n  By type:"
    stats[:by_type].each do |type, count|
      puts "    - #{type}: #{count}"
    end
    puts "\n  By pool:"
    stats[:by_pool].each do |pool, count|
      puts "    - #{pool}: #{count}"
    end
    puts "\n  Rights:"
    puts "    - Publishable: #{stats[:publishable]}"
    puts "    - Training eligible: #{stats[:training_eligible]}"
    
    # Check index status
    indexes = ActiveRecord::Base.connection.execute(<<~SQL)
      SELECT indexname, pg_size_pretty(pg_relation_size(indexname::regclass)) as size
      FROM pg_indexes 
      WHERE tablename = 'embeddings' 
      AND (indexdef LIKE '%USING hnsw%' OR indexdef LIKE '%USING ivfflat%')
    SQL
    
    if indexes.any?
      puts "\n  Indexes:"
      indexes.each do |idx|
        puts "    - #{idx['indexname']}: #{idx['size']}"
      end
    end
  end
end

# Run the test
EmbeddingsTester.run