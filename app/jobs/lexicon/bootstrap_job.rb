require 'set'

# PURPOSE: Stage 3 of the 9-stage pipeline - Lexicon Bootstrap
# Extracts canonical terms, surface forms, and builds the lexicon
# from content that has passed rights triage.
#
# Inputs: IngestItems with completed rights triage
# Outputs: LexiconAndOntology entries with canonical terms and surface forms

module Lexicon
  class BootstrapJob < Pipeline::BaseJob
    queue_as :pipeline
    
    def perform(pipeline_run_id)
      # BaseJob sets up @pipeline_run, @batch, @ekn via around_perform
      # Do NOT call super - BaseJob uses around_perform to wrap this method
      
      @extracted_terms = []
      items = items_to_process
      
      log_progress "Starting lexicon bootstrap for #{items.count} items"
      
      processed = 0
      failed = 0
      
      items.find_each do |item|
        begin
          process_item(item)
          processed += 1
          
          if processed % 10 == 0
            log_progress "Processed #{processed} IngestItems for lexicon extraction...", level: :debug
          end
        rescue => e
          log_progress "Failed to process item #{item.id}: #{e.message}", level: :error
          failed += 1
          item.update!(lexicon_status: 'failed', lexicon_metadata: { error: e.message })
        end
      end
      
      # Create lexicon entries
      create_lexicon_entries
      
      log_progress "✅ Lexicon bootstrap complete: #{processed} processed, #{failed} failed"
      
      # Track metrics
      track_metric :items_processed, processed
      track_metric :items_failed, failed
      track_metric :terms_extracted, @extracted_terms.size
      track_metric :lexicon_entries, LexiconAndOntology.count
      
      # Update batch status
      @batch.update!(status: 'lexicon_completed')
    end
    
    private
    
    def items_to_process
      # CRITICAL: Items must have completed rights triage AND be ready for lexicon processing
      # Check both triage_status (from Rights stage) and lexicon_status
      @batch.ingest_items
        .where(triage_status: 'completed')
        .where(lexicon_status: ['pending', nil])  # Ready for lexicon extraction
        .where(quarantined: [false, nil])
    end
    
    def process_item(item)
      return if item.content.blank?
      
      # Use the term extraction service
      result = Lexicon::TermExtractionService.new(
        content: item.content,
        metadata: item.metadata
      ).extract
      
      if result[:success]
        # Add provenance_and_rights_id and source_item_id from item to each extracted term
        terms_with_rights = result[:terms].map do |term|
          term.merge(
            provenance_and_rights_id: item.provenance_and_rights_id,
            source_item_id: item.id
          )
        end
        
        @extracted_terms.concat(terms_with_rights)
        
        item.update!(
          lexicon_status: 'extracted',
          lexicon_metadata: { 
            terms_count: result[:terms].size,
            extracted_at: Time.current 
          }
          # Note: pool_status: 'pending' moved to after successful lexicon entry creation
        )
      else
        raise result[:error]
      end
    end
    
    def create_lexicon_entries
      # Normalize and deduplicate terms
      service = Lexicon::NormalizationService.new(@extracted_terms)
      normalized_terms = service.normalize_and_deduplicate
      
      # Track which items actually contributed to persisted entries
      contributing_item_ids = Set.new
      
      # Use transaction to ensure atomicity
      ApplicationRecord.transaction do
        normalized_terms.each do |term_data|
          lexicon_entry = LexiconAndOntology.find_or_initialize_by(
            term: term_data[:canonical_term]
          )
          
          # Get rights_id from term data or use batch fallback
          rights_id = term_data[:provenance_and_rights_id] || batch_rights_fallback&.id
          
          if rights_id.nil?
            raise Pipeline::MissingRightsError, 
                  "No provenance_and_rights available for term '#{term_data[:canonical_term]}'. " \
                  "Ensure all IngestItems have associated ProvenanceAndRights records."
          end
          
          # Log which rights_id was chosen
          if term_data[:provenance_and_rights_id]
            log_progress "Using rights_id #{rights_id} for term '#{term_data[:canonical_term]}'", level: :debug
          else
            log_progress "Using batch fallback rights_id #{rights_id} for term '#{term_data[:canonical_term]}'", level: :debug
          end
          
          # Merge surface forms
          existing_surface = lexicon_entry.surface_forms || []
          new_surface = (existing_surface + (term_data[:surface_forms] || [])).uniq
          
          lexicon_entry.update!(
            provenance_and_rights_id: rights_id,
            definition: term_data[:canonical_description] || 'Extracted term',
            surface_forms: new_surface,
            pool_association: (term_data[:term_type].presence || 'general'),  # Fixed: use term_type
            is_canonical: true,
            valid_time_start: Time.current
          )
          
          # Record contributing items only after successful persistence
          (term_data[:source_item_ids] || []).each { |sid| contributing_item_ids << sid }
        end
        
        # Mark only contributing items as pool-ready
        if contributing_item_ids.any?
          @batch.ingest_items
            .where(id: contributing_item_ids.to_a)
            .where(lexicon_status: 'extracted')
            .update_all(pool_status: 'pending')
        end
        
        # Track why items weren't marked pool-ready
        non_contributing_items = @batch.ingest_items
          .where(lexicon_status: 'extracted')
          .where.not(id: contributing_item_ids.to_a)
        
        if non_contributing_items.any?
          non_contributing_items.each do |item|
            reason = "All #{item.lexicon_metadata['terms_count']} terms were duplicates of already-processed terms"
            item.update!(
              pool_status: 'skipped',
              pool_metadata: { 
                skip_reason: reason,
                skipped_at: Time.current
              }
            )
          end
          log_progress "Skipped #{non_contributing_items.count} items (all terms were duplicates)", level: :info
        end
      end
      
      log_progress "Marked #{contributing_item_ids.size} items as pool-ready", level: :debug
    end
    
    def collect_stage_metrics
      {
        items_processed: @metrics[:items_processed] || 0,
        items_failed: @metrics[:items_failed] || 0,
        terms_extracted: @metrics[:terms_extracted] || 0,
        lexicon_entries: @metrics[:lexicon_entries] || 0
      }
    end
    
    def batch_rights_fallback
      # Memoize the batch-level fallback rights record
      @batch_rights_fallback ||= begin
        # Find the first ingest item with a provenance_and_rights record
        @batch.ingest_items
          .includes(:provenance_and_rights)
          .map(&:provenance_and_rights)
          .compact
          .first
      end
    end
  end
end
