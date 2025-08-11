#!/usr/bin/env ruby

# FULL ARCTIC RESEARCH MARKITDOWN TRANSFORMATION
# Transform sparse "Knowledge Islands" into rich interconnected ecosystem

puts "🚀 FULL ARCTIC RESEARCH MARKITDOWN TRANSFORMATION"
puts "="*70
start_time = Time.current

# Find Arctic Research EKN
ekn = Ekn.find_by(slug: "arctic-research")
unless ekn
  puts "❌ Arctic Research EKN not found!"
  exit 1
end

# Get current state for comparison
stats_service = EknStatsService.new(ekn)
before_stats = stats_service.comprehensive_stats

puts "📊 BEFORE STATE:"
puts "   Entities: #{before_stats[:total_nodes]}"
puts "   Relationships: #{before_stats[:total_relationships]}"  
puts "   Density: #{(before_stats[:density] * 100).round(4)}%"
puts "   Documents: #{before_stats[:total_documents]}"

# Get all Arctic PDFs
pdf_dir = "/Volumes/jer4TBv3/enliterator/arctic_research"
pdf_files = Dir.glob("#{pdf_dir}/*.pdf").sort
puts "\n🎯 TARGET: Process #{pdf_files.count} Arctic Research PDFs"

# Create production batch
batch = ekn.ingest_batches.create!(
  name: "Arctic Research - Full MarkItDown Transformation",
  source_type: "production_markitdown",
  metadata: {
    description: "Complete Arctic Research transformation: Knowledge Islands → Rich Ecosystem",
    pdf_count: pdf_files.count,
    source_directory: pdf_dir,
    processing_method: "markitdown_token_aware_routing",
    demo_preparation: true,
    expected_impact: "2000%+ content increase, rich connectivity"
  }
)

puts "📦 Created production batch: #{batch.name} (ID: #{batch.id})"
puts "\n🔄 PROCESSING ALL #{pdf_files.count} PDFs..."

# Process all PDFs with comprehensive tracking
successful = 0
failed = 0
total_content = 0
total_tokens = 0
tier_1_count = 0
tier_2_count = 0
skipped_count = 0

pdf_files.each_with_index do |pdf_file, i|
  filename = File.basename(pdf_file)
  progress = "#{i+1}/#{pdf_files.count}"
  
  puts "\n#{progress}: #{filename}"
  
  begin
    # Create IngestItem
    file_size = File.size(pdf_file)
    item = batch.ingest_items.create!(
      file_path: pdf_file,
      media_type: "document",
      size_bytes: file_size,
      triage_status: "pending"
    )
    
    # Process with TriageService → MarkItDown
    triage_service = Ingest::TriageService.new(item)
    result = triage_service.call
    
    # Reload item to get updated data
    item.reload
    
    if result[:success] && item.content.present?
      successful += 1
      chars = item.content_length_chars || 0
      tokens = item.estimated_tokens || 0
      total_content += chars
      total_tokens += tokens
      
      # Track routing tiers
      case item.routing_tier
      when "tier_1" then tier_1_count += 1
      when "tier_2" then tier_2_count += 1
      else skipped_count += 1
      end
      
      puts "   ✅ SUCCESS: #{chars.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse} chars, #{tokens.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse} tokens"
      puts "      Model: #{item.extraction_model_used}, Tier: #{item.routing_tier}"
    else
      failed += 1
      puts "   ❌ FAILED: #{result[:error] || 'No content extracted'}"
    end
    
    # Progress indicator
    if (i + 1) % 5 == 0
      puts "\n📈 Progress Report (#{i+1}/#{pdf_files.count}):"
      puts "   Success: #{successful}, Failed: #{failed}"
      puts "   Content: #{total_content.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse} chars total"
    end
    
  rescue => e
    failed += 1
    puts "   ❌ ERROR: #{e.message}"
  end
end

processing_time = ((Time.current - start_time) / 60.0).round(2)

puts "\n" + "="*70
puts "🏁 FULL PROCESSING COMPLETE!"
puts "="*70

puts "\n📊 FINAL RESULTS:"
puts "   Successful: #{successful}/#{pdf_files.count} (#{((successful.to_f/pdf_files.count)*100).round(1)}%)"
puts "   Failed: #{failed}/#{pdf_files.count}"
puts "   Processing Time: #{processing_time} minutes"

puts "\n📈 CONTENT EXTRACTION:"
puts "   Total Characters: #{total_content.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
puts "   Total Tokens: #{total_tokens.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
puts "   Average per PDF: #{(total_content/[successful,1].max).to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse} chars"

puts "\n🎯 AI MODEL ROUTING:"
puts "   Tier 1 (gpt-5): #{tier_1_count} documents"
puts "   Tier 2 (gpt-4.1-mini): #{tier_2_count} documents" 
puts "   Skipped (too large): #{skipped_count} documents"

if successful >= (pdf_files.count * 0.8)  # 80% success rate
  puts "\n✅ TRANSFORMATION SUCCESSFUL!"
  puts "🎉 Arctic Research ready for demo - Knowledge Islands → Rich Ecosystem"
  
  # Get updated stats for comparison
  after_stats = stats_service.comprehensive_stats
  puts "\n📊 TRANSFORMATION IMPACT:"
  puts "   Documents: #{before_stats[:total_documents]} → #{after_stats[:total_documents]} (+#{after_stats[:total_documents] - before_stats[:total_documents]})"
  puts "   Content available for knowledge graph enhancement"
  puts "   Demo narrative: Sparse connectivity → Rich interconnected insights"
  
else
  puts "\n⚠️  PARTIAL SUCCESS - Review failed items for optimization"
end

puts "\n🚀 Arctic Research MarkItDown transformation complete!"
puts "Ready for knowledge graph assembly and demo preparation."