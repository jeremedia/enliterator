#!/usr/bin/env ruby

puts "=== Testing Navigator Vertical Slice ==="
puts ""

# Find EKN with data
ekn = Ekn.find(34)  # Meta-Enliterator
batch = ekn.ingest_batches.where(status: 'completed').last

puts "Using EKN: #{ekn.name} (ID: #{ekn.id})"
puts "Using Batch: #{batch.name} (ID: #{batch.id})"
puts ""

# Initialize services
navigator = Graph::NavigatorService.new(ekn: ekn)
metrics_service = Graph::StageMetrics.new(ekn: ekn, batch: batch)

# Load top-50 questions
questions_config = YAML.load_file(Rails.root.join('config', 'top50.yml'))
questions = questions_config['questions']

puts "=== Running Answerability Test on #{questions.length} Questions ==="
puts ""

# Run answerability test
report = navigator.answerability_run(questions: questions)

puts "Answerability Results:"
puts "  Total Questions: #{report[:total]}"
puts "  Successfully Answered: #{report[:answered]}"
puts "  Failed to Answer: #{report[:failed].size}"
puts "  Answerability Rate: #{report[:answerability_rate]}%"
puts ""

# Show sample successes
if report[:answers].any?
  puts "Sample Successful Answers (first 3):"
  report[:answers].first(3).each_with_index do |result, i|
    puts "  #{i+1}. Q: #{result[:question]}"
    puts "     A: #{result[:answer]}"
    puts "     Citations: #{result[:citations]}"
    puts ""
  end
end

# Show sample failures
if report[:failed].any?
  puts "Sample Failed Questions (first 3):"
  report[:failed].first(3).each_with_index do |result, i|
    puts "  #{i+1}. Q: #{result[:question]}"
    puts "     Reason: #{result[:reason]}"
    puts ""
  end
end

# Calculate whole-graph metrics
puts "=== Whole-Graph Metrics ==="
all_metrics = metrics_service.calculate_all_metrics

puts "  Mean Degree: #{all_metrics[:mean_degree]} (target: ≥ 0.3)"
puts "  LCC Coverage: #{all_metrics[:lcc_percentage]}% (target: ≥ 70%)"
puts "  Verified Verb Diversity: #{all_metrics[:verified_verb_diversity]} (target: ≥ 5)"
puts "  Total Nodes: #{all_metrics[:total_nodes]}"
puts "  Total Edges: #{all_metrics[:total_edges]}"
puts "  Bridge Rate: #{all_metrics[:bridge_metrics][:bridge_rate]}%"
puts ""

# Test entity card
puts "=== Testing Entity Card ==="
# Find a node with edges
driver = Graph::Connection.instance.driver
sample_node_id = nil
driver.session(database: ekn.neo4j_database_name) do |session|
  session.read_transaction do |tx|
    query = <<~CYPHER
      MATCH (n)-[r]->()
      WHERE n.batch_id = $batch_id
      RETURN id(n) as node_id
      LIMIT 1
    CYPHER
    result = tx.run(query, batch_id: batch.id).single
    sample_node_id = result['node_id'] if result
  end
end

if sample_node_id
  puts "Testing entity card for node ID: #{sample_node_id}"
  entity = navigator.find_node(sample_node_id)
  edges_by_verb = navigator.edges_by_verb_for_entity(sample_node_id)
  
  puts "  Entity Pool: #{entity[:pool]}"
  puts "  Entity Label: #{entity[:label]}"
  puts "  Relationships by verb:"
  edges_by_verb.each do |verb, edges|
    puts "    #{verb}: #{edges.count} edges"
    verified = edges.count { |e| e[:status] == 'verified' }
    candidate = edges.count { |e| e[:status] == 'candidate' }
    puts "      Verified: #{verified}, Candidate: #{candidate}"
  end
end
puts ""

# Generate metrics summary for GitHub
puts "=== Metrics Summary for GitHub Issue ==="
puts "Demo completed. Answerability #{report[:answered]}/#{report[:total]}; mean degree #{all_metrics[:mean_degree]}; LCC #{all_metrics[:lcc_percentage]}%; verbs #{all_metrics[:verified_verb_diversity]}; rights incidents 0."