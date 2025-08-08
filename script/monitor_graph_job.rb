#!/usr/bin/env ruby

pr = EknPipelineRun.find(37)
puts "Pipeline ##{pr.id} Status: #{pr.status}"
puts "Stage: #{pr.current_stage} (#{pr.current_stage_number}/9)"

if pr.error_message
  puts "\nError message:"
  puts pr.error_message
end

# Check if any data was loaded
driver = Graph::Connection.instance.driver
ekn_db = "ekn-#{pr.ekn_id}"
begin
  session = driver.session(database: ekn_db)
  node_count = session.run("MATCH (n) RETURN count(n) as count").single[:count]
  puts "\nNeo4j database: #{ekn_db}"
  puts "Nodes loaded: #{node_count}"
  
  if node_count > 0
    result = session.run("MATCH (n) RETURN labels(n)[0] as label, count(n) as count")
    puts "\nNode types:"
    result.each { |r| puts "  #{r[:label]}: #{r[:count]}" }
  end
rescue => e
  puts "\nNeo4j error: #{e.message}"
ensure
  session&.close
end

# Check latest failed job
failed = SolidQueue::FailedExecution.order(created_at: :desc).first
if failed && failed.created_at > 1.minute.ago && failed.job.class_name == "Graph::AssemblyJob"
  puts "\n" + "="*60
  puts "GRAPH JOB FAILURE ANALYSIS"
  puts "="*60
  
  error_msg = failed.error["message"]
  backtrace = failed.error["backtrace"] || []
  
  # Find the real error (not state transition)
  if error_msg && !error_msg.include?("transition")
    puts "Primary error: #{error_msg}"
  end
  
  # Find relevant backtrace lines
  relevant_lines = backtrace.select { |line| 
    line.include?("enliterator") && 
    !line.include?("mark_stage_failed") && 
    !line.include?("aasm") &&
    !line.include?("base_job")
  }
  
  if relevant_lines.any?
    puts "\nRelevant backtrace:"
    relevant_lines.first(5).each { |line| puts "  #{line}" }
  end
  
  # Try to find the root cause
  if backtrace.any? { |line| line.include?("neo4j") }
    puts "\n⚠️ Neo4j-related error detected"
  end
  
  if backtrace.any? { |line| line.include?("connection") }
    puts "\n⚠️ Connection error detected"
  end
end

# Check if job is still running
running = SolidQueue::ClaimedExecution.joins(:job).where("solid_queue_jobs.class_name = ?", "Graph::AssemblyJob").any?
puts "\n⏳ Graph job still running: #{running}"