#!/usr/bin/env ruby

# Test triaging a single item to find the exact error

batch = IngestBatch.last
item = batch.ingest_items.where(triage_status: 'failed').first

if item.nil?
  puts "No failed items found. Getting first pending item..."
  item = batch.ingest_items.where(triage_status: 'pending').first
end

if item.nil?
  puts "No items to test!"
  exit 1
end

puts "Testing item ##{item.id}: #{File.basename(item.file_path)}"
puts "Current triage_status: #{item.triage_status}"
puts "Current triage_error: #{item.triage_error}"
puts

# Reset the item
item.update!(
  triage_status: 'pending',
  triage_error: nil,
  provenance_and_rights_id: nil,
  training_eligible: nil,
  publishable: nil,
  quarantined: nil,
  quarantine_reason: nil
)

puts "Reset item to pending state"
puts

# Try to triage it
begin
  puts "Getting inferred rights..."
  inferred_rights = Rights::InferenceService.new(item).infer
  
  puts "Inferred confidence: #{inferred_rights[:confidence]}"
  
  if inferred_rights[:confidence] < 0.7
    puts "Low confidence, would quarantine"
    
    # Quarantine with exact code from TriageJob
    item.update!(
      quarantined: true,
      triage_status: 'quarantined',
      quarantine_reason: "Low confidence rights inference: #{inferred_rights[:confidence]}"
    )
    
    rights_record = ProvenanceAndRights.create!(
      source_ids: [item.source_hash || item.file_path],
      collection_method: inferred_rights[:method] || inferred_rights[:collection_method] || 'file_system',
      consent_status: 'unknown',
      license_type: 'unspecified',
      valid_time_start: Time.current,
      source_owner: inferred_rights[:owner] || inferred_rights[:source_owner] || 'unknown',
      publishability: false,
      training_eligibility: false,
      quarantined: true,
      custom_terms: {
        'source_type' => inferred_rights[:source_type] || 'unknown',
        'confidence' => inferred_rights[:confidence],
        'signals' => inferred_rights[:signals],
        'attribution' => inferred_rights[:attribution],
        'inferred' => true,
        'quarantine_reason' => "Low confidence: #{inferred_rights[:confidence]}"
      }
    )
    
    item.update!(provenance_and_rights_id: rights_record.id)
    puts "✅ Item quarantined successfully"
    
  else
    puts "High confidence, attaching rights"
    
    # Map consent status (exact code from TriageJob)
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
    
    # Map license type (exact code from TriageJob)
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
      when /ccbync$/, /ccbync[^a-z]/, /noncommercial/
        'cc_by_nc'
      when /ccbyncsa/
        'cc_by_nc_sa'
      when /ccbynd/, /noderivs/, /noderivatives/
        'cc_by_nd'
      when /ccbyncnd/
        'cc_by_nc_nd'
      when /proprietary/, /copyright/, /allrightsreserved/
        'proprietary'
      when /publicdomain/, /pd/, /cc0/
        'public_domain'
      when /fairuse/
        'fair_use'
      when /mit/, /apache/, /gpl/, /bsd/, /isc/, /custom/
        'custom'
      when /inferred/, /assumed/, /permissive/
        'cc_by'
      else
        'unspecified'
      end
    end
    
    rights_record = ProvenanceAndRights.create!(
      source_ids: [item.source_hash || item.file_path],
      collection_method: inferred_rights[:method] || inferred_rights[:collection_method] || 'file_system',
      consent_status: consent_status,
      license_type: license_type,
      valid_time_start: Time.current,
      source_owner: inferred_rights[:owner] || inferred_rights[:source_owner] || 'inferred',
      publishability: inferred_rights[:publishable] || false,
      training_eligibility: inferred_rights[:trainable] || false,
      quarantined: false,
      custom_terms: {
        'source_type' => inferred_rights[:source_type] || 'inferred',
        'confidence' => inferred_rights[:confidence],
        'signals' => inferred_rights[:signals],
        'attribution' => inferred_rights[:attribution],
        'inferred' => true,
        'inferred_publishable' => inferred_rights[:publishable],
        'inferred_trainable' => inferred_rights[:trainable]
      }
    )
    
    item.update!(
      triage_status: 'completed',
      provenance_and_rights_id: rights_record.id,
      training_eligible: rights_record.training_eligibility,
      publishable: rights_record.publishability,
      lexicon_status: 'pending'
    )
    
    puts "✅ Rights attached successfully"
    puts "  Training eligible: #{rights_record.training_eligibility}"
    puts "  Publishable: #{rights_record.publishability}"
  end
  
rescue => e
  puts "❌ Error: #{e.message}"
  puts e.backtrace.first(10).join("\n")
  
  # Update item with error
  item.update!(triage_status: 'failed', triage_error: e.message)
end