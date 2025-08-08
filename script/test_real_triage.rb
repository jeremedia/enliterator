#!/usr/bin/env ruby

# Test the actual Rights::TriageJob with real InferenceService

batch = IngestBatch.last
item = batch.ingest_items.second  # Get second item (first was already updated)

puts "Testing real Rights inference for item #{item.id}"
puts "File: #{item.file_path}"
puts "Initial triage_status: #{item.triage_status}"
puts "Content sample length: #{item.content_sample&.length || 0}"

# Reset the item to pending state
item.update!(
  triage_status: 'pending',
  provenance_and_rights_id: nil,
  training_eligible: nil,
  publishable: nil
)

puts "\nReset item to pending state"

# Test the InferenceService directly
inference_service = Rights::InferenceService.new(item)
inferred_rights = inference_service.infer

puts "\nInferred rights from InferenceService:"
inferred_rights.each do |key, value|
  puts "  #{key}: #{value.inspect}"
end

# Now test creating ProvenanceAndRights with the actual inferred rights
begin
  puts "\nAttempting to create ProvenanceAndRights with actual inferred rights..."
  
  # Map consent status
  consent = inferred_rights[:consent] || inferred_rights[:consent_status]
  consent_status = case consent.to_s.downcase
  when 'explicit', 'yes', 'granted', 'explicit_consent'
    'explicit_consent'
  when 'implicit', 'assumed', 'implicit_consent'
    'implicit_consent'
  when 'no', 'denied', 'refused', 'no_consent'
    'no_consent'
  when 'withdrawn', 'revoked'
    'withdrawn'
  else
    inferred_rights[:confidence].to_f >= 0.8 ? 'implicit_consent' : 'unknown'
  end
  
  # Map license type
  license = inferred_rights[:license]
  license_type = if license.blank?
    'unspecified'
  else
    normalized = license.to_s.downcase.gsub(/[\s\-_]/, '')
    case normalized
    when /cc0/, /creativecommons0/
      'cc0'
    when /ccby$/, /ccby[^a-z]/, /creativecommonsby$/, /attribution$/
      'cc_by'
    when /ccbysa/, /creativecommonsbysa/, /sharealike/
      'cc_by_sa'
    else
      'cc_by'  # Default permissive
    end
  end
  
  rights_record = ProvenanceAndRights.create!(
    # Required fields
    source_ids: [item.source_hash || item.file_path],
    collection_method: inferred_rights[:method] || inferred_rights[:collection_method] || 'file_system',
    consent_status: consent_status,
    license_type: license_type,
    
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
  
rescue => e
  puts "❌ Error: #{e.message}"
  puts e.backtrace.first(10).join("\n")
end