#!/usr/bin/env ruby

# PRODUCTION DEPLOYMENT: Arctic Research MarkItDown Reprocessing
puts "🚀 ARCTIC RESEARCH MARKITDOWN REPROCESSING"
puts "="*60

# Find the Arctic Research EKN
ekn = Ekn.find_by(slug: "arctic-research")
unless ekn
  puts "❌ Arctic Research EKN not found!"
  exit 1
end

puts "📊 Current State Analysis:"
puts "   EKN: #{ekn.name}"
puts "   Current ingest items: #{ekn.ingest_items.count}"
puts "   Current batches: #{ekn.ingest_batches.count}"

# Check available PDFs
pdf_dir = "/Volumes/jer4TBv3/enliterator/arctic_research"
pdf_files = Dir.glob("#{pdf_dir}/*.pdf").sort
puts "   Available PDFs: #{pdf_files.count}"

# Create new batch for MarkItDown processing
batch = ekn.ingest_batches.create!(
  name: "Arctic Research - MarkItDown Enhanced Processing",
  source_type: "markitdown_reprocessing",
  metadata: {
    description: "Full Arctic Research reprocessing with MarkItDown integration",
    pdf_count: pdf_files.count,
    source_directory: pdf_dir,
    processing_method: "markitdown_with_token_routing"
  }
)

puts "\n📦 Created new batch: #{batch.name} (ID: #{batch.id})"

# Process first 3 PDFs as validation (before committing to all 25)
test_files = pdf_files.first(3)
puts "\n🧪 Processing first 3 PDFs as validation:"

successful = 0
failed = 0

test_files.each_with_index do |pdf_file, i|
  filename = File.basename(pdf_file)
  puts "\n#{i+1}/3: Processing #{filename}"
  
  begin
    # Create IngestItem
    file_size = File.size(pdf_file)
    item = batch.ingest_items.create!(
      file_path: pdf_file,
      media_type: "application/pdf",
      size_bytes: file_size,
      triage_status: "pending"
    )
    
    # Process with TriageService (which routes to MarkItDown)
    triage_service = Ingest::TriageService.new(item)
    result = triage_service.call
    
    if result[:success]
      successful += 1
      puts "   ✅ SUCCESS: #{result[:content_length_chars]} chars, #{result[:estimated_tokens]} tokens"
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
puts "   Successful: #{successful}/3"
puts "   Failed: #{failed}/3"
puts "   Success Rate: #{((successful.to_f/3)*100).round(1)}%"

if successful >= 2  # At least 2/3 success rate
  puts "\n✅ VALIDATION PASSED! Ready for full processing."
  puts "📝 Next: Run full 25 PDF processing when ready"
else
  puts "\n❌ VALIDATION FAILED! Need debugging before full processing."
end

puts "\n🏁 Arctic Research MarkItDown integration validation complete!"