#!/usr/bin/env ruby
# frozen_string_literal: true

# Meta-Enliteration Stage 2: Rights & Provenance
# Sets appropriate rights for the Enliterator codebase

require_relative '../config/environment'

class MetaEnliterationRights
  def self.process_batch(batch_id)
    batch = IngestBatch.find(batch_id)
    
    puts "=== Stage 2: Rights & Provenance ==="
    puts "Processing batch: #{batch.name}"
    puts "Items to process: #{batch.ingest_items.count}"
    
    # Create or find the rights record for our codebase
    rights = ProvenanceAndRights.find_or_create_by!(
      source_owner: 'Enliterator Project',
      license_type: 'proprietary' # Internal proprietary code
    ) do |r|
      r.source_ids = ['enliterator_codebase_v1']
      r.collection_method = 'internal_development'
      r.consent_status = 'explicit_consent' # We own this code
      r.collectors = ['Enliterator Development Team']
      r.custom_terms = {
        'name' => 'Enliterator Internal License',
        'allow_public_display' => false, # Internal use only
        'allow_training' => true, # Yes, for meta-enliteration
        'description' => 'Internal codebase for creating the first Enliterated Knowledge Navigator'
      }
      r.training_eligibility = true
      r.publishability = false # Internal use, not for public distribution
      r.quarantined = false
    end
    
    puts "\nRights record: #{rights.id}"
    puts "  Training eligible: #{rights.training_eligibility}"
    puts "  Publishability: #{rights.publishability}"
    puts "  Consent: #{rights.consent_status}"
    
    # Apply rights to all items
    processed = 0
    batch.ingest_items.find_each do |item|
      item.update!(
        provenance_and_rights_id: rights.id,
        triage_status: 'completed',
        triage_metadata: {
          rights_assigned_at: Time.current,
          auto_triaged: true,
          reason: 'Internal codebase - auto-approved for training'
        }
      )
      processed += 1
      print "." if processed % 10 == 0
    end
    
    puts "\n\n✓ Rights assigned to #{processed} items"
    
    # Update batch status
    batch.update!(
      status: 'triage_completed',
      metadata: batch.metadata.merge(
        rights_processing: {
          completed_at: Time.current,
          items_processed: processed,
          rights_id: rights.id
        }
      )
    )
    
    puts "✓ Batch status updated to: #{batch.status}"
    
    # Verify all items have rights
    items_without_rights = batch.ingest_items.where(provenance_and_rights_id: nil).count
    if items_without_rights > 0
      puts "⚠️  Warning: #{items_without_rights} items still without rights"
    else
      puts "✓ All items have rights assigned"
    end
    
    # Show summary
    puts "\n=== Rights Summary ==="
    puts "Total items: #{batch.ingest_items.count}"
    puts "Training eligible: #{batch.ingest_items.joins(:provenance_and_rights).where(provenance_and_rights: { training_eligibility: true }).count}"
    puts "Completed triage: #{batch.ingest_items.triage_status_completed.count}"
    puts "Quarantined: #{batch.ingest_items.triage_status_quarantined.count}"
    
    batch
  end
end

# Run if executed directly
if __FILE__ == $0
  batch_id = ARGV[0] || 7 # Default to our meta-enliteration batch
  MetaEnliterationRights.process_batch(batch_id)
end