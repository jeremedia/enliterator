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
      # BaseJob sets up @pipeline_run, @batch, @ekn
      super
      
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
      log_progress "Failed to triage item #{item.id}: #{e.message}", level: :error
      item.update!(triage_status: 'failed', triage_error: e.message)
    end

    def quarantine_item(item, inferred_rights)
      item.update!(
        quarantined: true,
        triage_status: 'quarantined',
        quarantine_reason: "Low confidence rights inference: #{inferred_rights[:confidence]}"
      )
      
      log_progress "Quarantined item #{item.id}: #{item.file_path}", level: :warn

      # Still create a ProvenanceAndRights record, but mark as uncertain
      ProvenanceAndRights.create!(
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
    end

    def attach_rights(item, inferred_rights)
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

      item.update!(
        triage_status: 'completed',
        provenance_and_rights_id: rights_record.id,
        training_eligible: rights_record.training_eligibility,
        publishable: rights_record.publishability
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
        'triage_quarantined'
      else
        'triage_completed'
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