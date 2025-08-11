# frozen_string_literal: true

module Ingest
  # Service for routing files through the appropriate content extraction pathway
  # Primary path: MarkItDown for supported formats (PDF, DOCX, PPTX, etc.)  
  # Fallback path: Legacy extraction for unsupported formats
  class TriageService < ApplicationService
    
    attr_reader :ingest_item, :options
    
    def initialize(ingest_item, options = {})
      @ingest_item = ingest_item
      @options = options
    end
    
    def call
      Rails.logger.info "Triaging IngestItem ##{ingest_item.id}: #{File.basename(ingest_item.file_path)}"
      
      # Update triage status
      ingest_item.update!(triage_status: 'in_progress')
      
      # Detect media type and format support
      detection_result = MediaTypeDetector.new(ingest_item.file_path).call
      
      # Update media type if needed
      ingest_item.update!(media_type: detection_result[:media_type]) if ingest_item.media_type == 'unknown'
      
      # Route to appropriate extraction method
      if detection_result[:markitdown_supported] && should_use_markitdown?
        route_to_markitdown(detection_result)
      else
        route_to_legacy_extraction(detection_result)
      end
      
      # Mark triage as completed
      ingest_item.update!(triage_status: 'completed')
      
      Rails.logger.info "✅ Triage completed for IngestItem ##{ingest_item.id}"
      
      {
        success: true,
        extraction_method: ingest_item.extraction_method,
        routing_info: ingest_item.markitdown_metadata&.dig('routing_info'),
        media_type: ingest_item.media_type
      }
      
    rescue => e
      handle_triage_error(e)
    end
    
    private
    
    def should_use_markitdown?
      # Use MarkItDown unless explicitly disabled
      !options[:disable_markitdown] && File.exist?(ingest_item.file_path)
    end
    
    def route_to_markitdown(detection_result)
      Rails.logger.info "Routing to MarkItDown for IngestItem ##{ingest_item.id}"
      
      begin
        # Call TokenAwareMarkitdownService
        markitdown_result = TokenAwareMarkitdownService.new(ingest_item.file_path, options).call
        
        if markitdown_result[:success]
          # MarkItDown successful - update IngestItem with results
          update_with_markitdown_success(markitdown_result, detection_result)
        else
          # MarkItDown failed - fall back to legacy extraction
          Rails.logger.warn "MarkItDown failed for #{ingest_item.file_path}: #{markitdown_result[:error]}"
          route_to_legacy_extraction(detection_result, markitdown_fallback: markitdown_result)
        end
        
      rescue => e
        Rails.logger.error "MarkItDown service error: #{e.message}"
        route_to_legacy_extraction(detection_result, markitdown_error: e.message)
      end
    end
    
    def route_to_legacy_extraction(detection_result, markitdown_info = {})
      Rails.logger.info "Routing to legacy extraction for IngestItem ##{ingest_item.id}"
      
      # Call ContentExtractionService with legacy method
      extraction_result = ContentExtractionService.new(ingest_item, 
        method: 'legacy', 
        detection_result: detection_result
      ).call
      
      # Update IngestItem with legacy extraction results
      update_with_legacy_extraction(extraction_result, detection_result, markitdown_info)
    end
    
    def update_with_markitdown_success(markitdown_result, detection_result)
      routing_info = markitdown_result[:routing_info]
      metadata = markitdown_result[:metadata]
      
      # CRITICAL: Sanitize content for PostgreSQL - remove null bytes
      content = markitdown_result[:content]&.gsub("\0", '') || ''
      
      update_data = {
        extraction_method: 'markitdown',
        content: content, 
        content_sample: content[0..4999], # First 5000 chars for rights inference
        content_length_chars: metadata[:content_length_chars],
        estimated_tokens: metadata[:estimated_tokens],
        extraction_model_used: routing_info[:model],
        routing_tier: routing_info[:status],
        markitdown_metadata: {
          routing_info: routing_info,
          original_metadata: metadata,
          detection_result: detection_result,
          processed_at: Time.current.iso8601
        }
      }
      
      ingest_item.update!(update_data)
      
      Rails.logger.info "Updated IngestItem ##{ingest_item.id} with MarkItDown results: " \
                       "#{metadata[:estimated_tokens]} tokens, #{routing_info[:status]} tier"
    end
    
    def update_with_legacy_extraction(extraction_result, detection_result, markitdown_info)
      # Legacy extraction - read file content directly if not already done
      if ingest_item.content.blank? && File.exist?(ingest_item.file_path)
        begin
          full_content = File.read(ingest_item.file_path, encoding: 'UTF-8', invalid: :replace, undef: :replace)
          content_sample = full_content[0..4999]
        rescue => e
          Rails.logger.warn "Could not read content from #{ingest_item.file_path}: #{e.message}"
          full_content = ""
          content_sample = ""
        end
      else
        full_content = ingest_item.content
        content_sample = ingest_item.content_sample
      end
      
      update_data = {
        extraction_method: 'legacy',
        content: full_content,
        content_sample: content_sample,
        content_length_chars: full_content.length,
        estimated_tokens: nil, # Legacy method doesn't estimate tokens
        extraction_model_used: nil,
        routing_tier: nil,
        markitdown_metadata: {
          detection_result: detection_result,
          legacy_extraction: true,
          markitdown_attempted: markitdown_info.present?,
          markitdown_fallback_reason: markitdown_info[:error] || markitdown_info[:markitdown_error],
          processed_at: Time.current.iso8601
        }
      }
      
      ingest_item.update!(update_data)
      
      Rails.logger.info "Updated IngestItem ##{ingest_item.id} with legacy extraction: " \
                       "#{full_content.length} chars"
    end
    
    def handle_triage_error(error)
      Rails.logger.error "Triage failed for IngestItem ##{ingest_item.id}: #{error.message}"
      Rails.logger.error error.backtrace.join("\n") if Rails.env.development?
      
      ingest_item.update!(
        triage_status: 'failed',
        triage_error: error.message,
        markitdown_metadata: {
          error: error.message,
          error_type: error.class.name,
          failed_at: Time.current.iso8601
        }
      )
      
      {
        success: false,
        error: error.message,
        error_type: error.class.name
      }
    end
  end
end