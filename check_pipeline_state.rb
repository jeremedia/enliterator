#!/usr/bin/env ruby

# Check current pipeline state for Arctic Research
ekn = Ekn.find_by(slug: "arctic-research")
batch = ekn.ingest_batches.last  # Latest batch with 24 PDFs

puts "🔍 CURRENT PIPELINE STATE ANALYSIS"
puts "="*50

puts "📊 Batch Status:"
puts "   Name: #{batch.name}"
puts "   Status: #{batch.status}"
puts "   Items: #{batch.ingest_items.count}"

puts "\n📈 Content Ready for Pipeline:"
total_chars = batch.ingest_items.sum(:content_length_chars)
total_tokens = batch.ingest_items.sum(:estimated_tokens)
puts "   Total Characters: #{total_chars.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
puts "   Total Tokens: #{total_tokens.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"

puts "\n🔄 Pipeline Stage Status:"
puts "   Stage 1 (Intake): ✅ Complete - #{batch.ingest_items.count} PDFs processed"
puts "   Stage 2 (Rights): #{batch.ingest_items.where('quarantined IS NOT TRUE OR quarantined IS NULL').count}/#{batch.ingest_items.count} cleared"

# Check pipeline completion status
lexicon_complete = batch.respond_to?(:lexicon_bootstrap_completed?) ? batch.lexicon_bootstrap_completed? : false
pools_complete = batch.respond_to?(:pool_extraction_completed?) ? batch.pool_extraction_completed? : false
graph_complete = batch.graph_assembled_at.present?

puts "   Stage 3 (Lexicon): #{lexicon_complete ? '✅ Complete' : '❌ Pending'}"
puts "   Stage 4 (Pools): #{pools_complete ? '✅ Complete' : '❌ Pending'}"
puts "   Stage 5 (Graph): #{graph_complete ? '✅ Complete' : '❌ Pending'}"

puts "\n🎯 Current Knowledge Graph:"
stats_service = EknStatsService.new(ekn)
current_stats = stats_service.basic_stats
puts "   Entities: #{current_stats[:total_nodes]}"
puts "   Relationships: #{current_stats[:total_relationships]}"

# Check what needs to be run
puts "\n🚀 Pipeline Execution Plan:"
if !lexicon_complete
  puts "   ➡️ Next: Execute Stage 3 (Lexicon Bootstrap)"
elsif !pools_complete  
  puts "   ➡️ Next: Execute Stage 4 (Pool Filling)"
elsif !graph_complete
  puts "   ➡️ Next: Execute Stage 5 (Graph Assembly)"  
else
  puts "   ✅ All stages complete - Ready for chord diagram!"
end

puts "\n📊 Batch ID for pipeline execution: #{batch.id}"