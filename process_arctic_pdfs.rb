#!/usr/bin/env ruby

# PRODUCTION DEPLOYMENT: Arctic Research MarkItDown Enhancement
puts "🚀 ARCTIC RESEARCH MARKITDOWN ENHANCEMENT"
puts "="*60

# Find the restored Arctic Research EKN
ekn = Ekn.find_by(slug: "arctic-research")
unless ekn
  puts "❌ Arctic Research EKN not found!"
  exit 1
end

puts "📊 Current State Analysis:"
puts "   EKN: #{ekn.name} (ID: #{ekn.id})"
puts "   Current ingest items: #{ekn.ingest_items.count}"
puts "   Current batches: #{ekn.ingest_batches.count}"

# Check available PDFs
pdf_dir = "/Volumes/jer4TBv3/enliterator/arctic_research"
pdf_files = Dir.glob("#{pdf_dir}/*.pdf").sort
puts "   Available PDFs: #{pdf_files.count}"

# Check current knowledge graph state
stats_service = EknStatsService.new(ekn)
current_stats = stats_service.basic_stats
puts "\n📈 Current Knowledge Graph:"
puts "   Entities: #{current_stats[:total_nodes]}"
puts "   Relationships: #{current_stats[:total_relationships]}"
puts "   Density: #{(stats_service.comprehensive_stats[:density] * 100).round(4)}%"

# Create new batch for MarkItDown processing
batch = ekn.ingest_batches.create!(
  name: "Arctic Research - MarkItDown PDF Enhancement",
  source_type: "markitdown_enhancement",
  metadata: {
    description: "Process 25 Arctic Research PDFs with MarkItDown to transform sparse knowledge graph",
    pdf_count: pdf_files.count,
    source_directory: pdf_dir,
    processing_method: "markitdown_with_token_routing",
    goal: "Transform Knowledge Islands into Connected Ecosystem"
  }
)

puts "\n📦 Created enhancement batch: #{batch.name} (ID: #{batch.id})"

# Process first 5 PDFs as comprehensive validation
test_files = pdf_files.first(5)
puts "\n🧪 Processing first 5 PDFs for validation:"

successful = 0
failed = 0
total_content = 0
total_tokens = 0

test_files.each_with_index do |pdf_file, i|
  filename = File.basename(pdf_file)
  puts "\n#{i+1}/5: Processing #{filename}"
  
  begin
    # Create IngestItem
    file_size = File.size(pdf_file)
    item = batch.ingest_items.create!(
      file_path: pdf_file,
      media_type: "document", 
      size_bytes: file_size,
      triage_status: "pending"
    )
    
    # Process with TriageService (routes to MarkItDown)
    triage_service = Ingest::TriageService.new(item)
    result = triage_service.call
    
    if result[:success]
      successful += 1
      chars = result[:content_length_chars] || 0
      tokens = result[:estimated_tokens] || 0
      total_content += chars
      total_tokens += tokens
      
      puts "   ✅ SUCCESS: #{chars} chars, #{tokens} tokens"
      puts "      Model: #{result[:extraction_model_used]}, Tier: #{result[:routing_tier]}"
    else
      failed += 1
      puts "   ❌ FAILED: #{result[:error]}"
    end
    
  rescue => e
    failed += 1
    puts "   ❌ ERROR: #{e.message}"
  end
end

puts "\n📊 Validation Results:"
puts "   Successful: #{successful}/5"
puts "   Failed: #{failed}/5"
puts "   Success Rate: #{((successful.to_f/5)*100).round(1)}%"
puts "   Total Content: #{total_content} characters"
puts "   Total Tokens: #{total_tokens} tokens"

if successful >= 4  # At least 4/5 success rate
  puts "\n✅ VALIDATION PASSED! Ready for full 25 PDF processing."
  puts "📊 Projected full processing:"
  puts "   Estimated content: ~#{(total_content * 5).to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse} characters"
  puts "   Estimated tokens: ~#{(total_tokens * 5).to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse} tokens"
  puts "\n🚀 This will transform the Arctic Research knowledge graph!"
else
  puts "\n❌ VALIDATION FAILED! Need debugging before full processing."
end

puts "\n🏁 Arctic Research MarkItDown enhancement validation complete!"