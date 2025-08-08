#!/usr/bin/env ruby
# Clean Slate Pipeline Script
# Purpose: Destroy all failed attempts and prepare for ONE successful Meta-Enliterator creation

require_relative '../config/environment'

puts "\n" + "="*80
puts "CLEAN SLATE PIPELINE PREPARATION"
puts "="*80
puts "\nGoal: Create ONE Meta-Enliterator through a complete pipeline run"
puts "Philosophy: Each attempt must be atomic - fully succeed or be destroyed"

# Analysis Phase
puts "\n📊 Current State Analysis:"
puts "-"*40

# Count existing mess
ekn_count = Ekn.count
batch_count = IngestBatch.count
run_count = EknPipelineRun.count
item_count = IngestItem.count

puts "EKNs: #{ekn_count} (should be 0 before starting)"
puts "Batches: #{batch_count} (should be 0)"
puts "Pipeline Runs: #{run_count} (should be 0)"
puts "Ingest Items: #{item_count} (should be 0)"

# Check for entities
entity_counts = {
  ideas: Idea.count,
  manifests: Manifest.count,
  experiences: Experience.count,
  relationals: Relational.count,
  evolutionaries: Evolutionary.count,
  practicals: Practical.count,
  emanations: Emanation.count
}

puts "\nEntity Counts:"
entity_counts.each { |type, count| puts "  #{type}: #{count}" }

# Neo4j check
begin
  driver = Graph::Connection.instance.driver
  session = driver.session
  result = session.run("MATCH (n) RETURN count(n) as count")
  neo4j_nodes = result.single['count']
  session.close
  puts "\nNeo4j Nodes: #{neo4j_nodes}"
rescue => e
  puts "\nNeo4j Error: #{e.message}"
end

# Decision Point
puts "\n" + "="*80
puts "DECISION REQUIRED"
puts "="*80

if ekn_count > 0 || batch_count > 0
  puts "\n⚠️  Found existing data from failed attempts"
  puts "This must be cleaned before creating the Meta-Enliterator"
  puts "\nOptions:"
  puts "1. Run: rails runner script/clean_slate_pipeline.rb --clean"
  puts "2. Manually clean and restart"
  
  if ARGV.include?('--clean')
    puts "\n🧹 CLEANING MODE ACTIVATED"
    puts "-"*40
    
    # Destroy in correct order to avoid foreign key violations
    print "Destroying all Pipeline Runs... "
    EknPipelineRun.destroy_all
    puts "✅"
    
    print "Destroying all Conversations... "
    Conversation.destroy_all if defined?(Conversation)
    puts "✅"
    
    print "Destroying all Ingest Items... "
    IngestItem.destroy_all
    puts "✅"
    
    print "Destroying all Batches... "
    IngestBatch.destroy_all
    puts "✅"
    
    print "Destroying all EKNs... "
    Ekn.destroy_all
    puts "✅"
    
    print "Destroying all Entities... "
    # Delete lexicon first (has foreign keys to provenance)
    LexiconEntry.delete_all if defined?(LexiconEntry)
    LexiconAndOntology.delete_all if defined?(LexiconAndOntology)
    
    # Use delete_all to avoid join table issues
    Idea.delete_all
    Manifest.delete_all
    Experience.delete_all
    Relational.delete_all
    Evolutionary.delete_all
    Practical.delete_all
    Emanation.delete_all
    ProvenanceAndRights.delete_all
    
    # Clean up join tables as well
    ActiveRecord::Base.connection.execute("DELETE FROM idea_manifests")
    ActiveRecord::Base.connection.execute("DELETE FROM manifest_experiences")
    ActiveRecord::Base.connection.execute("DELETE FROM idea_practicals")
    ActiveRecord::Base.connection.execute("DELETE FROM experience_practicals")
    ActiveRecord::Base.connection.execute("DELETE FROM idea_emanations")
    ActiveRecord::Base.connection.execute("DELETE FROM experience_emanations")
    ActiveRecord::Base.connection.execute("DELETE FROM emanation_ideas")
    ActiveRecord::Base.connection.execute("DELETE FROM emanation_relationals")
    ActiveRecord::Base.connection.execute("DELETE FROM practical_ideas")
    
    LexiconEntry.delete_all if defined?(LexiconEntry)
    LexiconAndOntology.delete_all if defined?(LexiconAndOntology)
    puts "✅"
    
    # Clean Neo4j (optional - be careful!)
    if ARGV.include?('--clean-neo4j')
      print "Cleaning Neo4j... "
      session = driver.session
      session.run("MATCH (n) DETACH DELETE n")
      session.close
      puts "✅"
    end
    
    puts "\n✅ DATABASE CLEANED - Ready for Meta-Enliterator creation"
  end
else
  puts "\n✅ Database is already clean!"
end

# Next Steps
puts "\n" + "="*80
puts "NEXT STEPS"
puts "="*80

puts <<~STEPS
  1. Fix identified bugs:
     - IngestItem error_message → triage_error
     - Neo4j transaction separation
     - Database creation before use
     - Extraction/rights processing
  
  2. Create Meta-Enliterator bundle:
     rails runner 'MetaEnliteration::BundleCreator.new.call'
  
  3. Run ONE pipeline:
     rails runner script/create_meta_enliterator.rb
  
  4. Verify success:
     - All 9 stages complete
     - Literacy score > 70
     - Can answer questions about Enliterator
  
  Remember: The Meta-Enliterator must be BORN, not assembled.
STEPS

puts "="*80