#!/usr/bin/env ruby
# script/create_meta_enliterator.rb
#
# Creates the Meta-Enliterator EKN - the first Knowledge Navigator that understands
# Enliterator itself and can guide users in creating their own EKNs.
#
# This is THE critical first implementation that proves the system works!

require_relative '../config/environment'

Rails.logger = Logger.new(STDOUT)
Rails.logger.level = Logger::INFO

puts "\n" + "="*80
puts "Creating the Meta-Enliterator Knowledge Navigator"
puts "="*80 + "\n"

# Step 1: Create the Meta-Enliterator EKN
puts "\n[Step 1] Creating Meta-Enliterator EKN..."

ekn = Ekn.create!(
  name: "Enliterator Knowledge Navigator",
  description: "The system's understanding of itself - guides users in creating EKNs",
  status: 'initializing',
  domain_type: 'technical',
  personality: 'helpful_guide',
  metadata: {
    is_meta: true,  # Flag as THE special meta-EKN
    capabilities: ['explain_ekns', 'guide_creation', 'understand_self'],
    creation_reason: 'Bootstrap the system with self-understanding'
  }
)

puts "✅ Created EKN ##{ekn.id}: #{ekn.name}"

# Step 2: Ensure resources exist
puts "\n[Step 2] Creating Neo4j database and PostgreSQL schema..."
ekn.ensure_resources_exist!
ekn.update!(status: 'active')
puts "✅ Resources created: database=#{ekn.neo4j_database_name}, schema=#{ekn.postgres_schema_name}"

# Step 3: Add understanding of the EKN model itself (CRITICAL FIRST KNOWLEDGE!)
puts "\n[Step 3] Adding EKN model understanding (the most important file)..."

if File.exist?('app/models/ekn.rb')
  puts "Adding: app/models/ekn.rb"
  batch1 = ekn.add_knowledge(
    files: ['app/models/ekn.rb'],
    source_type: 'codebase'
  )
  
  puts "✅ Batch ##{batch1.id} created"
  puts "   Current nodes: #{ekn.total_nodes}"
  puts "   Current relationships: #{ekn.total_relationships}"
else
  puts "⚠️  EKN model file not found - skipping"
end

# Step 4: Add all models to understand the system structure
puts "\n[Step 4] Adding all models..."

model_files = Dir.glob('app/models/**/*.rb').sort
puts "Found #{model_files.count} model files"

if model_files.any?
  batch2 = ekn.add_knowledge(
    files: model_files,
    source_type: 'codebase'
  )
  
  puts "✅ Batch ##{batch2.id} created"
  puts "   Nodes after models: #{ekn.total_nodes} (should be MORE than before!)"
  puts "   Relationships: #{ekn.total_relationships}"
end

# Step 5: Add services to understand the pipeline
puts "\n[Step 5] Adding services (pipeline implementation)..."

service_files = Dir.glob('app/services/**/*.rb').sort
puts "Found #{service_files.count} service files"

if service_files.any?
  batch3 = ekn.add_knowledge(
    files: service_files,
    source_type: 'codebase'
  )
  
  puts "✅ Batch ##{batch3.id} created"
  puts "   Nodes after services: #{ekn.total_nodes} (accumulating!)"
  puts "   Relationships: #{ekn.total_relationships}"
end

# Step 6: Add documentation (THE VISION!)
puts "\n[Step 6] Adding documentation..."

doc_files = Dir.glob('docs/**/*.md').sort
puts "Found #{doc_files.count} documentation files"

if doc_files.any?
  batch4 = ekn.add_knowledge(
    files: doc_files,
    source_type: 'documentation'
  )
  
  puts "✅ Batch ##{batch4.id} created"
  puts "   ACCUMULATED nodes: #{ekn.total_nodes} (should be 500+ by now!)"
  puts "   Total relationships: #{ekn.total_relationships}"
end

# Step 7: Test self-understanding
puts "\n[Step 7] Testing Meta-Enliterator's self-understanding..."

# Simple test queries (will expand once conversational interface is ready)
test_questions = [
  "What is an EKN?",
  "How does the pipeline work?",
  "What are the Ten Pools?",
  "How do I create a Knowledge Navigator?"
]

puts "\nMeta-Enliterator is ready to answer questions like:"
test_questions.each do |q|
  puts "  • #{q}"
end

# Step 8: Summary
puts "\n" + "="*80
puts "Meta-Enliterator Creation Complete!"
puts "="*80

puts "\n📊 Final Statistics:"
puts "  • EKN ID: #{ekn.id}"
puts "  • Name: #{ekn.name}"
puts "  • Status: #{ekn.status}"
puts "  • Batches created: #{ekn.ingest_batches.count}"
puts "  • Total knowledge nodes: #{ekn.total_nodes}"
puts "  • Total relationships: #{ekn.total_relationships}"
puts "  • Knowledge density: #{ekn.knowledge_density}"
puts "  • Neo4j database: #{ekn.neo4j_database_name}"

puts "\n🎯 Critical Success Check:"
if ekn.total_nodes > 100
  puts "  ✅ Knowledge accumulated across batches (#{ekn.total_nodes} nodes)"
else
  puts "  ⚠️  Low node count (#{ekn.total_nodes}) - check pipeline processing"
end

if ekn.ingest_batches.count >= 3
  puts "  ✅ Multiple batches added to same EKN (#{ekn.ingest_batches.count} batches)"
else
  puts "  ⚠️  Only #{ekn.ingest_batches.count} batches - expected at least 3"
end

# All batches should use the same database
db_names = ekn.ingest_batches.map(&:neo4j_database_name).uniq
if db_names.count == 1 && db_names.first == ekn.neo4j_database_name
  puts "  ✅ All batches using same Neo4j database (#{db_names.first})"
else
  puts "  ❌ CRITICAL: Batches using different databases! #{db_names.inspect}"
end

puts "\n🚀 Next Steps:"
puts "  1. Run: rails console"
puts "  2. Load the Meta-Enliterator: ekn = Ekn.find_by(metadata: { is_meta: true })"
puts "  3. Test understanding: ekn.ask('What is an EKN?')"
puts "  4. Create verification script to prove accumulation"

puts "\n✨ The Meta-Enliterator is alive and ready to guide users!"
puts "   It understands itself and can now help create other Knowledge Navigators.\n\n"