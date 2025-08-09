#!/usr/bin/env ruby

puts "=== Testing Stage 5.5 Comprehensive Metrics ==="

batch = IngestBatch.find(76)
ekn = batch.ekn

# Initialize metrics system
metrics_service = Graph::StageMetrics.new(ekn: ekn, batch: batch)

# Generate and display full report
puts metrics_service.generate_report

# Save metrics to file for documentation
File.write(
  "stage_5_5_metrics_#{Time.now.strftime('%Y%m%d_%H%M%S')}.txt",
  metrics_service.generate_report
)

puts "\nMetrics saved to file."

# Get raw metrics for analysis
all_metrics = metrics_service.calculate_all_metrics

# Display pool distribution
puts "\n=== Pool Distribution ==="
all_metrics[:graph_metrics][:pool_distribution].each do |pool, count|
  puts "  #{pool}: #{count}"
end

# Display verb distribution
puts "\n=== Top Verbs ==="
all_metrics[:diversity_metrics][:verb_distribution].first(10).each do |verb, count|
  puts "  #{verb}: #{count}"
end

# Check if ready for Stage 6
if all_metrics[:gate_status][:all_passed]
  puts "\n✅ Ready to proceed to Stage 6: Representations & Retrieval"
else
  puts "\n⚠️  Address failing gates before proceeding to Stage 6"
  
  # Show what needs improvement
  all_metrics[:gate_status][:gates].each do |gate, result|
    unless result[:passed]
      deficit = result[:threshold] - result[:value]
      puts "  #{gate}: needs +#{deficit.round(2)} to pass"
    end
  end
end