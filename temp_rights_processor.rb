#!/usr/bin/env ruby

# Helper methods (must be defined first)
def infer_rights_simple(item)
  # For Enliterator codebase - assume permissive rights for our own code
  # Since this is Meta-Enliterator processing its own codebase
  
  confidence = 0.8  # High confidence for own codebase
  source_type = 'internal'
  license = 'mit'  # Assume permissive license
  
  {
    source_type: source_type,
    license: license,
    attribution: 'Enliterator System',
    publishable: true,
    trainable: true,
    confidence: confidence,
    signals: { path: item.file_path, media_type: item.media_type }
  }
end

def quarantine_item(item, inferred_rights)
  # Create rights record for quarantined item
  rights_record = ProvenanceAndRights.create!(
    ingest_item: item,
    source_type: inferred_rights[:source_type] || 'unknown',
    license: inferred_rights[:license] || 'unknown',
    attribution: inferred_rights[:attribution],
    publishability: false,
    training_eligibility: false,
    confidence_score: inferred_rights[:confidence],
    metadata: {
      inferred: true,
      signals: inferred_rights[:signals],
      quarantined: true
    }
  )
  
  item.update!(
    triage_status: 'quarantined',
    provenance_and_rights_id: rights_record.id,
    triage_metadata: {
      quarantine_reason: "Low confidence rights inference: #{inferred_rights[:confidence]}",
      quarantined_at: Time.current
    }
  )
end

def attach_rights(item, inferred_rights)
  # Create rights record
  rights_record = ProvenanceAndRights.create!(
    ingest_item: item,
    source_type: inferred_rights[:source_type] || 'inferred',
    license: inferred_rights[:license] || 'inferred_permissive',
    attribution: inferred_rights[:attribution],
    publishability: inferred_rights[:publishable],
    training_eligibility: inferred_rights[:trainable],
    confidence_score: inferred_rights[:confidence],
    metadata: {
      inferred: true,
      signals: inferred_rights[:signals]
    }
  )
  
  # Update item with rights
  item.update!(
    triage_status: 'completed',
    provenance_and_rights_id: rights_record.id,
    training_eligible: rights_record.training_eligibility,
    publishable: rights_record.publishability
  )
end