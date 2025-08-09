#!/usr/bin/env ruby

# Script to verify parity between discovered and created relationships
# Usage: rails runner script/metrics/show_parity.rb [pipeline_run_id]

class RelationshipParityChecker
  attr_reader :run, :batch, :ekn

  def initialize(pipeline_run_id = nil)
    @run = pipeline_run_id ? EknPipelineRun.find(pipeline_run_id) : EknPipelineRun.last
    @batch = @run.ingest_batch
    @ekn = @batch.ekn
    @driver = Graph::Connection.instance.driver
  end

  def check_parity
    puts "\n" + "="*60
    puts "RELATIONSHIP CREATION PARITY CHECK"
    puts "="*60
    puts "Pipeline Run: ##{@run.id}"
    puts "Batch: #{@batch.name} (ID: #{@batch.id})"
    puts "EKN: #{@ekn.name}"
    puts "Database: #{@ekn.neo4j_database_name}"
    
    # Get metrics from pipeline run
    stage_metrics = @run.stage_metrics || {}
    rel_metrics = stage_metrics['relationships'] || {}
    
    discovered = rel_metrics['relationships_discovered'] || 0
    created = rel_metrics['relationships_created'] || 0
    
    # Count actual relationships in Neo4j
    actual_count = count_neo4j_relationships
    
    # Count by type
    relationships_by_type = count_by_type
    
    # Display results
    puts "\n" + "-"*40
    puts "METRICS FROM PIPELINE RUN:"
    puts "-"*40
    puts "Relationships discovered: #{discovered}"
    puts "Relationships created:    #{created}"
    puts "Creation rate:           #{calculate_percentage(created, discovered)}"
    
    puts "\n" + "-"*40
    puts "ACTUAL NEO4J STATE:"
    puts "-"*40
    puts "Total relationships:     #{actual_count}"
    puts "Parity with created:     #{actual_count == created ? '✅ MATCH' : "❌ MISMATCH (diff: #{actual_count - created})"}"
    
    puts "\n" + "-"*40
    puts "RELATIONSHIPS BY TYPE:"
    puts "-"*40
    relationships_by_type.each do |type, count|
      puts "  #{type}: #{count}"
    end
    
    # Check for creation errors
    if discovered > created
      puts "\n" + "-"*40
      puts "⚠️  MISSING RELATIONSHIPS: #{discovered - created}"
      puts "-"*40
      check_failed_creations
    end
    
    # Final verdict
    puts "\n" + "="*60
    if discovered == created && created == actual_count
      puts "✅ FULL PARITY ACHIEVED"
      puts "All discovered relationships successfully created in graph"
    else
      puts "❌ PARITY CHECK FAILED"
      puts "Investigation needed - check logs for creation errors"
    end
    puts "="*60
    
    # Return parity status
    discovered == created && created == actual_count
  end

  private

  def count_neo4j_relationships
    @driver.session(database: @ekn.neo4j_database_name) do |session|
      session.read_transaction do |tx|
        query = "MATCH ()-[r]->() WHERE type(r) <> 'HAS_RIGHTS' RETURN count(r) as count"
        result = tx.run(query)
        result.single['count']
      end
    end
  end

  def count_by_type
    @driver.session(database: @ekn.neo4j_database_name) do |session|
      session.read_transaction do |tx|
        query = "MATCH ()-[r]->() WHERE type(r) <> 'HAS_RIGHTS' RETURN type(r) as type, count(r) as count ORDER BY count DESC"
        result = tx.run(query)
        result.map { |row| [row['type'], row['count']] }.to_h
      end
    end
  end

  def check_failed_creations
    # Check recent failed jobs
    failed_jobs = SolidQueue::FailedExecution
                    .joins(:job)
                    .where(jobs: { class_name: 'Graph::RelationshipDiscoveryJob' })
                    .order(created_at: :desc)
                    .limit(5)
    
    if failed_jobs.any?
      puts "Recent failed relationship jobs:"
      failed_jobs.each do |failure|
        puts "  - #{failure.created_at}: #{failure.error['message']}"
      end
    else
      puts "No failed relationship discovery jobs found"
    end
  end

  def calculate_percentage(numerator, denominator)
    return "N/A" if denominator == 0
    percentage = (numerator.to_f / denominator * 100).round(1)
    "#{percentage}%"
  end
end

# Run the checker
if __FILE__ == $0
  pipeline_run_id = ARGV[0]&.to_i
  checker = RelationshipParityChecker.new(pipeline_run_id)
  
  parity_achieved = checker.check_parity
  
  # Exit with error code if parity not achieved
  exit(1) unless parity_achieved
end