# frozen_string_literal: true

module Ingest
  # Service for extracting content from various file formats
  # Handles both MarkItDown-generated Markdown and legacy file reading
  # Primary path: Process Markdown content from MarkItDown conversion
  # Fallback path: Direct file reading for unsupported formats
  class ContentExtractionService < ApplicationService
    
    attr_reader :ingest_item, :options, :method, :detection_result
    
    def initialize(ingest_item, options = {})
      @ingest_item = ingest_item
      @options = options
      @method = options[:method] || 'auto'
      @detection_result = options[:detection_result] || {}
    end
    
    def call
      Rails.logger.info "Extracting content for IngestItem ##{ingest_item.id} using #{method} method"
      
      case method
      when 'markitdown'
        process_markitdown_content
      when 'legacy'  
        process_legacy_content
      when 'auto'
        # Auto-detect based on existing data
        if ingest_item.extraction_method == 'markitdown'
          process_markitdown_content
        else
          process_legacy_content
        end
      else
        raise ArgumentError, "Unknown extraction method: #{method}"
      end
      
    rescue => e
      handle_extraction_error(e)
    end
    
    private
    
    def process_markitdown_content
      Rails.logger.info "Processing MarkItDown Markdown content for IngestItem ##{ingest_item.id}"
      
      # Content should already be stored from MarkItDown conversion
      content = ingest_item.content
      
      if content.blank?
        raise StandardError, "No MarkItDown content available for processing"
      end
      
      # Process Markdown content for downstream stages
      processed_content = {
        raw_content: content,
        processed_content: clean_markdown_content(content),
        content_type: 'markdown',
        source_method: 'markitdown',
        word_count: count_words(content),
        line_count: count_lines(content),
        has_structured_data: detect_structured_elements(content)
      }
      
      Rails.logger.info "Processed #{processed_content[:word_count]} words of Markdown content"
      
      {
        success: true,
        content_info: processed_content,
        extraction_method: 'markitdown',
        ready_for_lexicon: true,
        ready_for_pools: true
      }
    end
    
    def process_legacy_content
      Rails.logger.info "Processing legacy content for IngestItem ##{ingest_item.id}"
      
      # Read content if not already available
      content = ingest_item.content
      
      if content.blank?
        content = read_file_content(ingest_item.file_path)
        if content.present?
          ingest_item.update!(
            content: content,
            content_sample: content[0..4999],
            content_length_chars: content.length
          )
        end
      end
      
      # Process based on media type
      processed_content = case ingest_item.media_type
      when 'text', 'document'
        process_text_content(content)
      when 'data', 'structured'
        process_structured_content(content)  
      when 'code'
        process_code_content(content)
      when 'config'
        process_config_content(content)
      else
        process_generic_content(content)
      end
      
      Rails.logger.info "Processed #{processed_content[:word_count]} words of #{ingest_item.media_type} content"
      
      {
        success: true,
        content_info: processed_content,
        extraction_method: 'legacy',
        ready_for_lexicon: can_extract_lexicon?(processed_content),
        ready_for_pools: can_extract_pools?(processed_content)
      }
    end
    
    def read_file_content(file_path)
      return "" unless File.exist?(file_path)
      
      begin
        File.read(file_path, encoding: 'UTF-8', invalid: :replace, undef: :replace)
      rescue => e
        Rails.logger.warn "Could not read content from #{file_path}: #{e.message}"
        ""
      end
    end
    
    def clean_markdown_content(content)
      # Clean up MarkItDown output for better processing
      cleaned = content.dup
      
      # Remove excessive whitespace
      cleaned = cleaned.gsub(/\n{3,}/, "\n\n")
      
      # Normalize headers
      cleaned = cleaned.gsub(/^#+\s*$/, '') # Remove empty headers
      
      # Clean up table formatting issues
      cleaned = cleaned.gsub(/\|\s*\|/, '|') # Remove empty table cells
      
      cleaned.strip
    end
    
    def process_text_content(content)
      {
        raw_content: content,
        processed_content: content.strip,
        content_type: 'text',
        source_method: 'file_read',
        word_count: count_words(content),
        line_count: count_lines(content),
        has_structured_data: false
      }
    end
    
    def process_structured_content(content)
      # Detect JSON, XML, CSV, etc.
      structure_type = detect_structure_type(content)
      
      {
        raw_content: content,
        processed_content: content.strip,
        content_type: 'structured',
        structure_type: structure_type,
        source_method: 'file_read',
        word_count: count_words(content),
        line_count: count_lines(content),
        has_structured_data: true
      }
    end
    
    def process_code_content(content)
      {
        raw_content: content,
        processed_content: content.strip,
        content_type: 'code',
        source_method: 'file_read',
        word_count: count_words(content),
        line_count: count_lines(content),
        has_structured_data: detect_code_structure(content)
      }
    end
    
    def process_config_content(content)
      config_type = detect_config_type(ingest_item.file_path, content)
      
      {
        raw_content: content,
        processed_content: content.strip,
        content_type: 'config',
        config_type: config_type,
        source_method: 'file_read',
        word_count: count_words(content),
        line_count: count_lines(content),
        has_structured_data: true
      }
    end
    
    def process_generic_content(content)
      {
        raw_content: content,
        processed_content: content.strip,
        content_type: 'generic',
        source_method: 'file_read', 
        word_count: count_words(content),
        line_count: count_lines(content),
        has_structured_data: false
      }
    end
    
    # Utility methods
    
    def count_words(content)
      return 0 if content.blank?
      content.scan(/\w+/).length
    end
    
    def count_lines(content)
      return 0 if content.blank?
      content.lines.count
    end
    
    def detect_structured_elements(markdown_content)
      return false if markdown_content.blank?
      
      # Check for tables, lists, code blocks
      has_tables = markdown_content.include?('|')
      has_lists = markdown_content.match?(/^[\s]*[-*+]\s/)
      has_numbered_lists = markdown_content.match?(/^[\s]*\d+\.\s/)
      has_code_blocks = markdown_content.include?('```')
      has_headers = markdown_content.match?(/^#+\s/)
      
      has_tables || has_lists || has_numbered_lists || has_code_blocks || has_headers
    end
    
    def detect_structure_type(content)
      return 'unknown' if content.blank?
      
      # Try JSON first
      begin
        JSON.parse(content)
        return 'json'
      rescue JSON::ParserError
        # Not JSON, continue
      end
      
      # Check for XML
      if content.strip.start_with?('<') && content.strip.end_with?('>')
        return 'xml'
      end
      
      # Check for CSV (simple heuristic)
      if content.include?(',') && content.lines.first&.count(',') == content.lines.second&.count(',')
        return 'csv'
      end
      
      'unknown'
    end
    
    def detect_code_structure(content)
      # Simple heuristics for code structure
      has_functions = content.match?(/def\s+\w+|function\s+\w+|class\s+\w+/)
      has_imports = content.match?(/^(import|require|include|#include)/)
      has_comments = content.match?(/^\s*(#|\/\/|\/\*)/)
      
      has_functions || has_imports || has_comments
    end
    
    def detect_config_type(file_path, content)
      extension = File.extname(file_path).downcase
      
      case extension
      when '.yml', '.yaml'
        'yaml'
      when '.json'
        'json'
      when '.toml'
        'toml'
      when '.ini'
        'ini'
      when '.env'
        'env'
      else
        'unknown'
      end
    end
    
    def can_extract_lexicon?(processed_content)
      # Can extract lexicon if we have text content
      processed_content[:word_count] > 0
    end
    
    def can_extract_pools?(processed_content)
      # Can extract pools if we have meaningful content
      processed_content[:word_count] > 10 # Arbitrary minimum
    end
    
    def handle_extraction_error(error)
      Rails.logger.error "Content extraction failed for IngestItem ##{ingest_item.id}: #{error.message}"
      Rails.logger.error error.backtrace.join("\n") if Rails.env.development?
      
      {
        success: false,
        error: error.message,
        error_type: error.class.name,
        extraction_method: method,
        ready_for_lexicon: false,
        ready_for_pools: false
      }
    end
  end
end