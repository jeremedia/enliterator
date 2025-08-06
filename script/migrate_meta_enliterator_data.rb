#!/usr/bin/env ruby
# Migrate Meta-Enliterator data from default Neo4j database to isolated EKN database
# This copies only the Enliterator-specific nodes (not Burning Man data)

require_relative '../config/environment'

puts "\n" + "="*80
puts "Migrating Meta-Enliterator Data to Isolated Database"
puts "="*80

# Find the Meta-Enliterator EKN
ekn = IngestBatch.find_by(name: "Meta-Enliterator")

unless ekn
  puts "ERROR: Meta-Enliterator EKN not found!"
  puts "Run: rails runner script/create_meta_enliterator_ekn.rb first"
  exit 1
end

puts "\n1. Target EKN:"
puts "   Name: #{ekn.name}"
puts "   Neo4j Database: #{ekn.neo4j_database_name}"
puts "   PostgreSQL Schema: #{ekn.postgres_schema_name}"

# Connect to Neo4j
driver = Graph::Connection.instance.driver

# Strategy: We need to identify which nodes are from Enliterator vs Burning Man
# The Enliterator nodes should have names/labels related to code, not camps/art
puts "\n2. Analyzing source data in default database..."

session = driver.session # default database

# Get a sample of nodes to understand the data
result = session.run(<<~CYPHER)
  MATCH (n)
  WHERE n.name IS NOT NULL
  RETURN labels(n)[0] as label, n.name as name
  LIMIT 20
CYPHER

puts "   Sample nodes:"
enliterator_patterns = []
burning_man_patterns = []

result.each do |record|
  name = record['name']
  label = record['label']
  
  # Classify based on content
  if name =~ /camp|burn|playa|art|temple|man|festival|radical/i
    burning_man_patterns << "#{label}: #{name}"
  elsif name =~ /code|service|model|controller|pipeline|stage|job|task|ruby|rails/i
    enliterator_patterns << "#{label}: #{name}"
  end
end

if enliterator_patterns.any?
  puts "\n   Likely Enliterator nodes:"
  enliterator_patterns.first(5).each { |p| puts "     - #{p}" }
end

if burning_man_patterns.any?
  puts "\n   Likely Burning Man nodes:"
  burning_man_patterns.first(5).each { |p| puts "     - #{p}" }
end

session.close

# Since the data is mixed, we need a better strategy
# Let's look for nodes created around the time of batch #7
puts "\n3. Identifying Enliterator-specific nodes..."

# Get the batch #7 timestamps
batch7 = IngestBatch.find(7)
puts "   Batch #7 created at: #{batch7.created_at}"
puts "   Items: #{batch7.ingest_items.count}"

# Check if nodes have timestamps or batch references
session = driver.session
result = session.run(<<~CYPHER)
  MATCH (n)
  WHERE n.created_at IS NOT NULL OR n.batch_id IS NOT NULL
  RETURN n.created_at as created_at, n.batch_id as batch_id, labels(n)[0] as label
  LIMIT 5
CYPHER

has_timestamps = false
has_batch_ids = false

result.each do |record|
  has_timestamps = true if record['created_at']
  has_batch_ids = true if record['batch_id']
end

session.close

puts "   Nodes have timestamps: #{has_timestamps}"
puts "   Nodes have batch_ids: #{has_batch_ids}"

# Export and import strategy
puts "\n4. Migration Strategy:"

if has_batch_ids
  puts "   ✓ Nodes have batch_ids - can filter precisely!"
  puts "   Will copy nodes where batch_id = 7"
elsif has_timestamps
  puts "   ✓ Nodes have timestamps - can filter by date!"
  puts "   Will copy nodes created around #{batch7.created_at}"
else
  puts "   ⚠️  No clear way to distinguish datasets!"
  puts "   Options:"
  puts "   a) Copy ALL nodes (includes Burning Man data)"
  puts "   b) Filter by name patterns (risky, might miss data)"
  puts "   c) Start fresh with a new pipeline run"
end

# For now, let's document what we would do
puts "\n5. Migration Commands (NOT EXECUTED):"
puts "\n   # Export from default database:"
puts "   MATCH (n) WHERE n.batch_id = 7"
puts "   WITH collect(n) as nodes"
puts "   MATCH ()-[r]->() WHERE startNode(r).batch_id = 7 OR endNode(r).batch_id = 7"
puts "   RETURN nodes, collect(r) as relationships"
puts "\n   # Import to isolated database:"
puts "   Use APOC procedures or Neo4j import tools"

puts "\n" + "="*80
puts "Migration Analysis Complete"
puts "="*80
puts "\nRecommendation:"
puts "Since the data doesn't have clear batch_id markers, the cleanest approach is to:"
puts "\n1. Keep the mixed data in the default database for reference"
puts "\n2. Run a fresh pipeline on the Enliterator codebase:"
puts "   a) Create a new zip of the codebase"
puts "   b) Process it through the pipeline with the isolated EKN"
puts "   c) Data will go directly to the isolated database"
puts "\nThis ensures clean separation and proper isolation from the start."
puts "="*80