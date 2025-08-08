#!/usr/bin/env ruby

puts "Testing single item lexicon extraction with rights..."
puts

# Get one item with rights
item = IngestItem.joins(:provenance_and_rights).where(ingest_batch_id: 53).first

if item.nil?
  puts "❌ No items with rights found in batch 53"
  exit 1
end

puts "Using item ##{item.id}"
puts "  File: #{File.basename(item.file_path)}"
puts "  ProvenanceAndRights ID: #{item.provenance_and_rights_id}"
puts "  Content length: #{item.content&.length || 0} chars"

if item.content.blank?
  puts "❌ Item has no content"
  exit 1
end

# Test term extraction with rights
puts "\n1. Testing term extraction..."
puts "-"*40

service = Lexicon::TermExtractionService.new(
  content: item.content[0..500],  # Use just first 500 chars to speed up
  metadata: item.metadata
)

result = service.extract

if result[:success]
  puts "✅ Extraction successful"
  puts "   Terms found: #{result[:terms]&.count || 0}"
  
  if result[:terms]&.any?
    # Add rights to terms as the job would
    terms_with_rights = result[:terms].map do |term|
      term.merge(provenance_and_rights_id: item.provenance_and_rights_id)
    end
    
    puts "\n2. Testing normalization..."
    puts "-"*40
    
    # Normalize terms
    norm_service = Lexicon::NormalizationService.new(terms_with_rights)
    normalized = norm_service.normalize_and_deduplicate
    
    puts "✅ Normalization complete"
    puts "   Normalized terms: #{normalized.count}"
    
    # Check if rights preserved
    normalized.each do |term|
      if term[:provenance_and_rights_id]
        puts "   ✅ '#{term[:canonical_term]}' has rights_id: #{term[:provenance_and_rights_id]}"
      else
        puts "   ❌ '#{term[:canonical_term]}' missing rights_id!"
      end
    end
    
    puts "\n3. Testing LexiconAndOntology creation..."
    puts "-"*40
    
    # Try creating one entry
    first_term = normalized.first
    if first_term
      begin
        entry = LexiconAndOntology.find_or_initialize_by(
          term: first_term[:canonical_term]
        )
        
        entry.assign_attributes(
          provenance_and_rights_id: first_term[:provenance_and_rights_id],
          definition: first_term[:canonical_description] || 'Test term',
          surface_forms: first_term[:surface_forms],
          pool_association: 'general',
          is_canonical: true,
          valid_time_start: Time.current
        )
        
        if entry.save
          puts "✅ Successfully created/updated LexiconAndOntology entry"
          puts "   Term: #{entry.term}"
          puts "   Rights ID: #{entry.provenance_and_rights_id}"
          puts "   Valid: #{entry.valid?}"
        else
          puts "❌ Failed to save entry"
          puts "   Errors: #{entry.errors.full_messages.join(', ')}"
        end
      rescue => e
        puts "❌ Error creating entry: #{e.message}"
      end
    end
  else
    puts "⚠️ No terms extracted from content"
  end
else
  puts "❌ Extraction failed: #{result[:error]}"
end

puts "\n✅ Test complete!"