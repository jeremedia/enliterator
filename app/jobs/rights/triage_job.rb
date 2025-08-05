# frozen_string_literal: true

module Rights
  # Job to triage data items for rights and provenance
  # This is Stage 2 of the Zero-touch Pipeline
  # - Infers source and license signals from data
  # - Attaches ProvenanceAndRights to all items
  # - Derives publishability and training_eligibility
  # - Quarantines ambiguous items
  class TriageJob < ApplicationJob
    queue_as :pipeline

    def perform(ingest_batch_id)
      @batch = IngestBatch.find(ingest_batch_id)
      @triage_results = []

      Rails.logger.info "Starting rights triage for batch #{@batch.id}"

      @batch.ingest_items.pending_triage.find_each do |item|
        triage_item(item)
      end

      finalize_batch_triage
    end

    private

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
      Rails.logger.error "Failed to triage item #{item.id}: #{e.message}"
      item.update!(triage_status: 'failed', triage_error: e.message)
    end

    def quarantine_item(item, inferred_rights)
      item.update!(
        triage_status: 'quarantined',
        triage_metadata: {
          reason: 'Low confidence rights inference',
          confidence: inferred_rights[:confidence],
          inferred: inferred_rights.except(:confidence)
        }
      )

      # Create a provisional rights record for review
      rights = ProvenanceAndRights.create!(
        source_ids: [item.source_hash],
        collectors: inferred_rights[:collectors] || ['unknown'],
        collection_method: inferred_rights[:method] || 'unknown',
        consent_status: 'unknown',
        license_type: inferred_rights[:license] || 'unspecified',
        source_owner: inferred_rights[:owner],
        quarantined: true,
        custom_terms: {
          inferred: true,
          confidence: inferred_rights[:confidence]
        },
        valid_time_start: Time.current
      )

      item.update!(provenance_and_rights: rights)
    end

    def attach_rights(item, inferred_rights)
      # Create definitive rights record
      rights = ProvenanceAndRights.create!(
        source_ids: [item.source_hash],
        collectors: inferred_rights[:collectors] || [item.source_type],
        collection_method: inferred_rights[:method] || 'automated_ingestion',
        consent_status: inferred_rights[:consent] || 'unknown',
        license_type: inferred_rights[:license] || 'unspecified',
        source_owner: inferred_rights[:owner],
        embargo_until: inferred_rights[:embargo_until],
        custom_terms: inferred_rights[:custom_terms] || {},
        valid_time_start: Time.current
      )

      item.update!(
        provenance_and_rights: rights,
        triage_status: 'completed',
        triage_metadata: {
          confidence: inferred_rights[:confidence],
          method: inferred_rights[:inference_method]
        }
      )
    end

    def finalize_batch_triage
      completed_count = @triage_results.count { |r| r[:status] == 'completed' }
      quarantined_count = @triage_results.count { |r| r[:status] == 'quarantined' }
      failed_count = @triage_results.count { |r| r[:status] == 'failed' }

      @batch.update!(
        status: determine_batch_status(completed_count, quarantined_count, failed_count),
        metadata: @batch.metadata.merge(
          triage_results: {
            total: @triage_results.count,
            completed: completed_count,
            quarantined: quarantined_count,
            failed: failed_count,
            timestamp: Time.current
          }
        )
      )

      # Trigger next stage if successful
      if @batch.status == 'triage_completed'
        # TODO: Implement Lexicon::BootstrapJob
        # Lexicon::BootstrapJob.perform_later(@batch.id)
        Rails.logger.info "Batch #{@batch.id} ready for lexicon bootstrap stage"
      end
    end

    def determine_batch_status(completed, quarantined, failed)
      total = completed + quarantined + failed
      
      # Handle empty batch
      return 'triage_completed' if total == 0
      
      if failed > total * 0.1 # More than 10% failed
        'triage_failed'
      elsif quarantined > total * 0.5 # More than 50% quarantined
        'triage_needs_review'
      else
        'triage_completed'
      end
    end
  end
end