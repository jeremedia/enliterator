#!/usr/bin/env ruby
# Create the Meta-Enliterator
# This script creates the FIRST EKN by processing the Enliterator codebase
# It must succeed completely or fail and be cleaned

require_relative '../config/environment'

def detect_media_type(file_path)
  extension = File.extname(file_path).downcase
  
  case extension
  when '.rb' then 'code'
  when '.md', '.txt' then 'text'
  when '.yml', '.yaml' then 'config'
  when '.json', '.xml' then 'data'
  else 'unknown'
  end
end

puts "\n" + "="*80
puts "META-ENLITERATOR CREATION"
puts "="*80
puts "Creating the first Knowledge Navigator from Enliterator codebase"
puts "="*80

# Pre-flight checks
puts "\n🔍 Pre-flight Checks:"
puts "-"*40

# 1. Check database is clean
if Ekn.count > 0
  puts "❌ Database not clean! Found #{Ekn.count} existing EKNs"
  puts "   Run: rails runner script/clean_slate_pipeline.rb --clean"
  exit 1
end
puts "✅ Database is clean"

# 2. Check Neo4j connection
begin
  driver = Graph::Connection.instance.driver
  connectivity = driver.verify_connectivity
  puts "✅ Neo4j connected: #{Rails.application.config.neo4j[:url]}"
rescue => e
  puts "❌ Neo4j connection failed: #{e.message}"
  exit 1
end

# 3. Check OpenAI configuration
if ENV['OPENAI_API_KEY'].blank?
  puts "❌ OPENAI_API_KEY not set"
  exit 1
end
puts "✅ OpenAI configured"

# Create the Meta-EKN
puts "\n🚀 Creating Meta-Enliterator EKN:"
puts "-"*40

begin
  # Step 1: Create the EKN
  ekn = Ekn.create!(
    name: "Meta-Enliterator",
    domain_type: "technical",
    personality: "helpful_guide",
    status: "initializing",
    metadata: {
      is_meta: true,
      created_by: "create_meta_enliterator.rb",
      purpose: "The first Knowledge Navigator - understands Enliterator itself",
      capabilities: [
        "explain_enliterator_concepts",
        "guide_ekn_creation", 
        "understand_pipeline_stages",
        "demonstrate_knowledge_navigation"
      ]
    }
  )
  
  puts "✅ Created EKN ##{ekn.id}: #{ekn.name}"
  
  # Step 2: Gather Enliterator source files
  puts "\n📁 Gathering source files:"
  
  files = []
  
  # Core application code
  files += Dir.glob(Rails.root.join('app', '**', '*.rb'))
  puts "  - #{files.count} application files"
  
  # Documentation
  doc_files = Dir.glob(Rails.root.join('docs', '**', '*.md'))
  files += doc_files
  puts "  - #{doc_files.count} documentation files"
  
  # Key root files
  %w[README.md CLAUDE.md Gemfile].each do |file|
    path = Rails.root.join(file)
    if File.exist?(path)
      files << path.to_s
      puts "  - Added #{file}"
    end
  end
  
  # Filter out unwanted files
  files.reject! do |f|
    f.include?('/tmp/') || 
    f.include?('/log/') || 
    f.include?('/node_modules/') ||
    f.include?('.git/') ||
    f.include?('/storage/')
  end
  
  files = files.uniq
  puts "\n📊 Total files to process: #{files.count}"
  
  # Step 3: Create IngestBatch
  batch = ekn.ingest_batches.create!(
    name: "Enliterator Codebase",
    source_type: "mixed",
    status: "pending",
    metadata: {
      file_count: files.count,
      source_paths: files.first(10), # Sample for metadata
      processing_options: {
        started_by: "meta_enliterator_creation",
        auto_advance: true,
        skip_failed_items: false
      }
    }
  )
  
  puts "✅ Created IngestBatch ##{batch.id}"
  
  # Step 4: Create IngestItems
  print "Creating IngestItems... "
  
  files.each do |file_path|
    batch.ingest_items.create!(
      file_path: file_path,
      media_type: detect_media_type(file_path),
      triage_status: 'pending'
    )
  end
  
  puts "✅ Created #{batch.ingest_items.count} items"
  
  # Step 5: Create and start pipeline run
  puts "\n🏃 Starting Pipeline:"
  puts "-"*40
  
  pipeline_run = EknPipelineRun.create!(
    ekn: ekn,
    ingest_batch: batch,
    status: 'initialized',
    options: {
      started_by: 'meta_enliterator_creation',
      auto_advance: true,
      source_files: files.count,
      skip_failed_items: false
    }
  )
  
  puts "✅ Created Pipeline Run ##{pipeline_run.id}"
  
  # Step 6: Start the pipeline
  puts "\n▶️  Starting pipeline execution..."
  puts "   This will process through all 9 stages automatically"
  puts "   Monitor progress at: rails runner 'EknPipelineRun.find(#{pipeline_run.id}).stage_statuses'"
  
  # Start with intake
  Pipeline::IntakeJob.perform_later(pipeline_run.id)
  
  puts "\n✅ Pipeline started!"
  puts "\n" + "="*80
  puts "PIPELINE RUNNING"
  puts "="*80
  puts "\nThe Meta-Enliterator is being created..."
  puts "Check status with: rails runner 'puts EknPipelineRun.find(#{pipeline_run.id}).status'"
  puts "\nExpected stages:"
  puts "1. Intake - Read and hash files"
  puts "2. Rights - Assign provenance"
  puts "3. Lexicon - Extract terms"
  puts "4. Pools - Extract entities"
  puts "5. Graph - Build Neo4j graph"
  puts "6. Embeddings - Create vectors"
  puts "7. Literacy - Score completeness"
  puts "8. Deliverables - Generate outputs"
  puts "9. Fine-tuning - Train model"
  
rescue => e
  puts "\n❌ ERROR: #{e.message}"
  puts e.backtrace.first(5)
  
  # Clean up on failure
  if defined?(ekn) && ekn
    puts "\n🧹 Cleaning up failed attempt..."
    ekn.destroy
  end
  
  exit 1
end

puts "\n" + "="*80
puts "✨ Meta-Enliterator creation initiated!"
puts "="*80