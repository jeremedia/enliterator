#!/usr/bin/env ruby

puts "="*60
puts "TESTING LEXICON RIGHTS FIX"
puts "="*60
puts

# Find a batch with items that have ProvenanceAndRights
batch = IngestBatch.find(53)  # The micro test batch
puts "Using batch ##{batch.id}: #{batch.name}"
puts "Items in batch: #{batch.ingest_items.count}"

# Check ProvenanceAndRights status
items_with_rights = batch.ingest_items.joins(:provenance_and_rights).count
puts "Items with ProvenanceAndRights: #{items_with_rights}"

if items_with_rights == 0
  puts "\n❌ No items have ProvenanceAndRights! Cannot test fix."
  exit 1
end

# Reset lexicon status for testing
puts "\nResetting lexicon status for testing..."
batch.ingest_items.update_all(
  lexicon_status: 'pending',
  lexicon_metadata: nil,
  pool_status: nil
)

# Clear existing lexicon entries to test fresh creation
LexiconAndOntology.destroy_all
puts "Cleared existing lexicon entries"

# Create or find pipeline run
pr = EknPipelineRun.find_or_create_by(
  ekn: batch.ekn,
  ingest_batch: batch
) do |p|
  p.status = 'initialized'
  p.current_stage = 'lexicon'
  p.current_stage_number = 3
end

puts "\nUsing pipeline run ##{pr.id}"
puts "Current stage: #{pr.current_stage}"

# Run the Lexicon job directly
puts "\nRunning Lexicon::BootstrapJob..."
puts "-"*40

begin
  # Execute the job
  job = Lexicon::BootstrapJob.new
  job.instance_variable_set(:@pipeline_run, pr)
  job.instance_variable_set(:@batch, batch)
  job.instance_variable_set(:@ekn, pr.ekn)
  job.instance_variable_set(:@metrics, {})
  
  # Call perform directly
  job.perform(pr.id)
  
  puts "\n✅ Job completed successfully!"
  
  # Check results
  puts "\nResults:"
  puts "-"*40
  
  # Check lexicon entries
  lexicon_count = LexiconAndOntology.count
  puts "Lexicon entries created: #{lexicon_count}"
  
  if lexicon_count > 0
    # Check if entries have rights
    entries_with_rights = LexiconAndOntology.where.not(provenance_and_rights_id: nil).count
    puts "Entries with ProvenanceAndRights: #{entries_with_rights}"
    
    # Show sample entry
    sample = LexiconAndOntology.first
    puts "\nSample entry:"
    puts "  Term: #{sample.term}"
    puts "  Definition: #{sample.definition}"
    puts "  ProvenanceAndRights ID: #{sample.provenance_and_rights_id}"
    puts "  Surface forms: #{sample.surface_forms&.join(', ')}"
    puts "  Repr text: #{sample.repr_text.present? ? 'Generated' : 'Missing'}"
  else
    puts "⚠️ No lexicon entries created"
  end
  
  # Check item statuses
  puts "\nItem statuses:"
  puts "  Lexicon status 'extracted': #{batch.ingest_items.where(lexicon_status: 'extracted').count}"
  puts "  Pool status 'pending': #{batch.ingest_items.where(pool_status: 'pending').count}"
  
  # Check metrics
  metrics = job.instance_variable_get(:@metrics)
  puts "\nMetrics:"
  metrics.each do |key, value|
    puts "  #{key}: #{value}"
  end
  
rescue => e
  puts "\n❌ Job failed with error:"
  puts "  #{e.class}: #{e.message}"
  puts "\nBacktrace:"
  puts e.backtrace.first(5).map { |line| "  #{line}" }.join("\n")
  
  # Check if it's the rights validation error
  if e.message.include?("Provenance and rights")
    puts "\n⚠️ This is the rights validation error we're trying to fix!"
  end
end

puts "\n" + "="*60
puts "TEST COMPLETE"
puts "="*60