#!/usr/bin/env ruby

# Debug script to test Rights::TriageJob

batch = IngestBatch.last
item = batch.ingest_items.first

puts "Testing Rights::TriageJob with item #{item.id}"
puts "File: #{item.file_path}"
puts "Initial triage_status: #{item.triage_status}"

# Create a simple InferenceService mock result
inferred_rights = {
  license: 'cc_by',
  consent: 'implicit_consent',
  method: 'file_system',
  collection_method: 'file_system',
  owner: 'test_owner',
  source_owner: 'test_owner',
  confidence: 0.8,
  publishable: true,
  trainable: true,
  source_type: 'codebase',
  attribution: 'Test Attribution',
  signals: { test: true }
}

puts "\nInferred rights hash:"
puts inferred_rights.inspect

# Try to create ProvenanceAndRights directly (mimicking what TriageJob does)
begin
  puts "\nAttempting to create ProvenanceAndRights..."
  
  rights_record = ProvenanceAndRights.create!(
    # Required fields
    source_ids: [item.source_hash || item.file_path],
    collection_method: inferred_rights[:method] || inferred_rights[:collection_method] || 'file_system',
    consent_status: 'implicit_consent',
    license_type: 'cc_by',
    
    # CRITICAL: valid_time_start is NOT NULL
    valid_time_start: Time.current,
    
    # Optional fields
    source_owner: inferred_rights[:owner] || inferred_rights[:source_owner] || 'inferred',
    
    # Rights flags
    publishability: inferred_rights[:publishable] || false,
    training_eligibility: inferred_rights[:trainable] || false,
    quarantined: false,
    
    # Store additional data in custom_terms
    custom_terms: {
      'source_type' => inferred_rights[:source_type] || 'inferred',
      'confidence' => inferred_rights[:confidence],
      'signals' => inferred_rights[:signals],
      'attribution' => inferred_rights[:attribution],
      'inferred' => true
    }
  )
  
  puts "✅ ProvenanceAndRights created successfully! ID: #{rights_record.id}"
  
  # Update the item
  item.update!(
    triage_status: 'completed',
    provenance_and_rights_id: rights_record.id,
    training_eligible: rights_record.training_eligibility,
    publishable: rights_record.publishability,
    lexicon_status: 'pending'
  )
  
  puts "✅ IngestItem updated successfully!"
  puts "  triage_status: #{item.triage_status}"
  puts "  rights_id: #{item.provenance_and_rights_id}"
  puts "  training_eligible: #{item.training_eligible}"
  puts "  publishable: #{item.publishable}"
  puts "  lexicon_status: #{item.lexicon_status}"
  
rescue => e
  puts "❌ Error: #{e.message}"
  puts e.backtrace.first(5)
end