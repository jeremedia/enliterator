# frozen_string_literal: true

module Rights
  # Job to triage data items for rights and provenance
  # This is Stage 2 of the Zero-touch Pipeline
  # - Infers source and license signals from data
  # - Attaches ProvenanceAndRights to all items
  # - Derives publishability and training_eligibility
  # - Quarantines ambiguous items
  class TriageJob < Pipeline::BaseJob
    queue_as :pipeline

    def perform(pipeline_run_id)
      # BaseJob sets up @pipeline_run, @batch, @ekn via around_perform
      # Do NOT call super - BaseJob uses around_perform to wrap this method
      
      @triage_results = []
      
      log_progress "Starting rights triage for #{items_to_process.count} items"
      
      items_to_process.find_each.with_index do |item, index|
        triage_item(item)
        
        # Log progress every 25 items
        if (index + 1) % 25 == 0
          log_progress "Triaged #{index + 1} items...", level: :debug
        end
      end

      finalize_batch_triage
      
      # CRITICAL: Validate that we actually processed items
      if items_to_process.count > 0 && @triage_results.empty?
        raise Pipeline::InvalidDataError, "Rights stage found #{items_to_process.count} items to process but processed 0! Check triage_status values."
      end
      
      # Ensure at least some items are eligible for training/publishing
      eligible_count = @batch.ingest_items.where(training_eligible: true).count
      publishable_count = @batch.ingest_items.where(publishable: true).count
      
      if @batch.ingest_items.count > 0 && eligible_count == 0 && publishable_count == 0
        log_progress "⚠️ WARNING: No items marked as training eligible or publishable!", level: :warn
        # Don't fail here as this might be legitimate (all rights restricted)
      end
    end

    private
    
    def items_to_process
      @batch.ingest_items.where(triage_status: ['pending', nil])
    end

    def triage_item(item)
      return if item.file_path.blank?

      # Infer rights from various signals
      inferred_rights = Rights::InferenceService.new(item).infer

      if inferred_rights[:confidence] < 0.7
        quarantine_item(item, inferred_rights)
      else
        attach_rights(item, inferred_rights)
      end

      @triage_results << {
        item_id: item.id,
        status: item.triage_status,
        confidence: inferred_rights[:confidence]
      }
    rescue StandardError => e
      log_progress "Failed to triage item #{item.id}: #{e.message}", level: :error
      item.update!(triage_status: 'failed', triage_error: e.message)
    end

    def quarantine_item(item, inferred_rights)
      # CRITICAL: Mark the IngestItem as quarantined
      # This prevents it from being processed in later stages
      item.update!(
        quarantined: true,
        triage_status: 'quarantined',
        quarantine_reason: "Low confidence rights inference: #{inferred_rights[:confidence]}"
      )
      
      log_progress "Quarantined item #{item.id}: #{item.file_path}", level: :warn

      # CRITICAL: Create ProvenanceAndRights with CORRECT attributes
      # ProvenanceAndRights model expects: source_ids, collection_method, consent_status, license_type
      # Database schema does NOT have source_type - store in custom_terms instead
      # FIELD MAPPING: InferenceService returns 'owner' and 'method', we need 'source_owner' and 'collection_method'
      rights_record = ProvenanceAndRights.create!(
        # Required fields
        source_ids: [item.source_hash || item.file_path],  # Array of source identifiers
        collection_method: inferred_rights[:method] || inferred_rights[:collection_method] || 'file_system',
        consent_status: map_consent_status(inferred_rights),
        license_type: map_license_type(inferred_rights[:license]),
        
        # CRITICAL: valid_time_start is NOT NULL in schema - must be set
        valid_time_start: Time.current,
        
        # Optional fields that exist in the model
        source_owner: inferred_rights[:owner] || inferred_rights[:source_owner] || 'unknown',
        
        # Rights flags - these are derived by the model's callbacks
        publishability: false,  # Will be recalculated by derive_rights callback
        training_eligibility: false,  # Will be recalculated by derive_rights callback
        quarantined: true,  # Mark as quarantined
        
        # Store additional data in custom_terms JSON field
        custom_terms: {
          'source_type' => inferred_rights[:source_type] || 'unknown',
          'confidence' => inferred_rights[:confidence],
          'signals' => inferred_rights[:signals],
          'attribution' => inferred_rights[:attribution],
          'inferred' => true,
          'quarantine_reason' => "Low confidence: #{inferred_rights[:confidence]}"
        }
      )
      
      # CRITICAL: Update IngestItem with the rights record ID
      # The association is IngestItem belongs_to ProvenanceAndRights
      item.update!(provenance_and_rights_id: rights_record.id)
    end

    def attach_rights(item, inferred_rights)
      # CRITICAL: Create ProvenanceAndRights with CORRECT attributes
      # ProvenanceAndRights model expects: source_ids, collection_method, consent_status, license_type
      # Database schema does NOT have source_type - store in custom_terms instead
      # FIELD MAPPING: InferenceService returns 'owner' and 'method', we need 'source_owner' and 'collection_method'
      rights_record = ProvenanceAndRights.create!(
        # Required fields - these MUST be present
        source_ids: [item.source_hash || item.file_path],  # Array of source identifiers
        collection_method: inferred_rights[:method] || inferred_rights[:collection_method] || 'file_system',
        consent_status: map_consent_status(inferred_rights),
        license_type: map_license_type(inferred_rights[:license]),
        
        # CRITICAL: valid_time_start is NOT NULL in schema - must be set
        valid_time_start: Time.current,
        
        # Optional fields that exist in the model
        source_owner: inferred_rights[:owner] || inferred_rights[:source_owner] || 'inferred',
        
        # These will be overridden by derive_rights callback based on consent_status and license_type
        publishability: inferred_rights[:publishable] || false,
        training_eligibility: inferred_rights[:trainable] || false,
        quarantined: false,  # Not quarantined since confidence is high
        
        # Store additional data in custom_terms JSON field
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
      
      # CRITICAL: Update the IngestItem with rights information
      # The association is IngestItem belongs_to ProvenanceAndRights
      # Also copy the derived rights flags to IngestItem for quick filtering
      # CRITICAL: Set lexicon_status to 'pending' so next stage can process it
      item.update!(
        triage_status: 'completed',
        provenance_and_rights_id: rights_record.id,
        training_eligible: rights_record.training_eligibility,
        publishable: rights_record.publishability,
        lexicon_status: 'pending'  # Ready for lexicon extraction
      )
      
      log_progress "Rights attached to item #{item.id}: trainable=#{rights_record.training_eligibility}, publishable=#{rights_record.publishability}", level: :debug
    end

    def finalize_batch_triage
      completed = @triage_results.count { |r| r[:status] == 'completed' }
      quarantined = @triage_results.count { |r| r[:status] == 'quarantined' }
      failed = @triage_results.count { |r| r[:status] == 'failed' }
      
      log_progress "✅ Rights triage complete: #{completed} completed, #{quarantined} quarantined, #{failed} failed"
      
      # Track metrics
      track_metric :items_completed, completed
      track_metric :items_quarantined, quarantined
      track_metric :items_failed, failed
      track_metric :training_eligible, @batch.ingest_items.where(training_eligible: true).count
      track_metric :publishable, @batch.ingest_items.where(publishable: true).count

      # Update batch status
      batch_status = determine_batch_status(completed, quarantined, failed)
      @batch.update!(status: batch_status)
      
      if batch_status == 'triage_completed'
        log_progress "Batch #{@batch.id} ready for lexicon bootstrap stage"
      end
    end

    def determine_batch_status(completed, quarantined, failed)
      total = completed + quarantined + failed
      
      if failed > total * 0.5
        'triage_failed'
      elsif quarantined > total * 0.8
        'triage_needs_review'  # FIXED: Use valid enum value from IngestBatch model
      else
        'triage_completed'
      end
    end
    
    # CRITICAL: Map inferred consent to ProvenanceAndRights consent_status enum
    # Enum values: unknown, explicit_consent, implicit_consent, no_consent, withdrawn
    def map_consent_status(inferred_rights)
      consent = inferred_rights[:consent] || inferred_rights[:consent_status]
      
      case consent.to_s.downcase
      when 'explicit', 'yes', 'granted', 'explicit_consent'
        'explicit_consent'
      when 'implicit', 'assumed', 'implicit_consent'
        'implicit_consent'
      when 'no', 'denied', 'refused', 'no_consent'
        'no_consent'
      when 'withdrawn', 'revoked'
        'withdrawn'
      else
        # Default to implicit if we have high confidence, unknown otherwise
        inferred_rights[:confidence].to_f >= 0.8 ? 'implicit_consent' : 'unknown'
      end
    end
    
    # CRITICAL: Map inferred license to ProvenanceAndRights license_type enum
    # Enum values: unspecified, cc0, cc_by, cc_by_sa, cc_by_nc, cc_by_nc_sa, cc_by_nd, cc_by_nc_nd,
    #              proprietary, public_domain, fair_use, custom
    def map_license_type(license)
      return 'unspecified' if license.blank?
      
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
        'custom'  # Open source licenses stored as custom with details in custom_terms
      when /inferred/, /assumed/, /permissive/
        # For inferred permissive licenses, use cc_by as a safe default
        'cc_by'
      else
        'unspecified'
      end
    end
    
    def collect_stage_metrics
      {
        items_completed: @metrics[:items_completed] || 0,
        items_quarantined: @metrics[:items_quarantined] || 0,
        items_failed: @metrics[:items_failed] || 0,
        training_eligible: @metrics[:training_eligible] || 0,
        publishable: @metrics[:publishable] || 0
      }
    end
  end
end