#!/usr/bin/env ruby
# Approve quarantined items for meta-enliteration

# Update quarantined items to completed for meta-enliteration
batch = IngestBatch.find(4)
updated_count = 0

batch.ingest_items.where(triage_status: 'quarantined').find_each do |item|
  # Update the rights record to mark as approved
  if item.provenance_and_rights
    item.provenance_and_rights.update!(
      consent_status: 'explicit_consent',
      license_type: 'proprietary',
      source_owner: 'Enliterator Project',
      quarantined: false,
      custom_terms: {
        approved_for: 'meta_enliteration',
        approved_by: 'system',
        approved_at: Time.current
      }
    )
  end
  
  item.update!(
    triage_status: 'completed',
    triage_metadata: (item.triage_metadata || {}).merge(
      manual_approval: true,
      approved_for: 'meta_enliteration',
      approved_at: Time.current
    )
  )
  updated_count += 1
end

puts "Updated #{updated_count} items from quarantined to completed"
puts "New triage status counts: #{batch.ingest_items.group(:triage_status).count}"

# Update batch status
batch.update!(status: 'triage_completed')
puts "Batch status updated to: #{batch.status}"