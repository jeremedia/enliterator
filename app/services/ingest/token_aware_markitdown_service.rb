# frozen_string_literal: true

module Ingest
  # Service for converting documents to Markdown with intelligent AI model routing
  # Integrates Microsoft's MarkItDown for PDF-to-Markdown conversion
  # Routes to appropriate OpenAI models based on token limits
  class TokenAwareMarkitdownService < ApplicationService
    
    # Token limits for different model tiers (with safety margins)
    TIER_1_LIMIT = 380_000  # gpt-5 (400K context, 380K safety)
    TIER_2_LIMIT = 1_000_000  # gpt-4.1-mini-2025-04-14 (1.047M context, 1M safety)
    
    # Supported file formats for MarkItDown
    SUPPORTED_FORMATS = %w[.pdf .docx .pptx .xlsx .md .txt .html .rtf .odt .jpg .jpeg .png .bmp .gif .svg].freeze
    
    class ConversionError < StandardError; end
    class UnsupportedFormatError < StandardError; end
    class TokenLimitExceededError < StandardError; end
    
    attr_reader :file_path, :options
    
    def initialize(file_path, options = {})
      @file_path = file_path
      @options = options
    end
    
    def self.supported_formats
      SUPPORTED_FORMATS
    end
    
    def call
      convert_with_routing
    rescue => e
      handle_error(e)
    end
    
    def convert_with_routing
      validate_file!
      
      Rails.logger.info "Starting MarkItDown conversion for: #{file_path}"
      
      # Step 1: Convert to Markdown using MarkItDown
      markdown_content = convert_to_markdown(file_path)
      
      # Step 2: Estimate tokens accurately
      estimated_tokens = estimate_tokens_accurately(markdown_content)
      
      # Step 3: Route to appropriate extraction model
      routing_decision = route_extraction_model(estimated_tokens)
      
      # Step 4: Return structured result
      {
        success: true,
        content: markdown_content,
        routing_info: routing_decision,
        metadata: {
          service: self.class.name,
          file_path: file_path,
          file_size_bytes: File.size(file_path),
          content_length_chars: markdown_content.length,
          estimated_tokens: estimated_tokens,
          timestamp: Time.current.iso8601,
          supported_formats: SUPPORTED_FORMATS
        }
      }
    rescue ConversionError, UnsupportedFormatError, TokenLimitExceededError => e
      {
        success: false,
        error: e.message,
        error_type: e.class.name,
        routing_info: { status: 'failed', reason: e.message },
        metadata: build_error_metadata(e)
      }
    end
    
    private
    
    def validate_file!
      unless File.exist?(file_path)
        raise ConversionError, "File not found: #{file_path}"
      end
      
      extension = File.extname(file_path).downcase
      unless SUPPORTED_FORMATS.include?(extension)
        raise UnsupportedFormatError, "Unsupported format: #{extension}. Supported: #{SUPPORTED_FORMATS.join(', ')}"
      end
      
      # Check file size (reasonable limit: 100MB)
      file_size = File.size(file_path)
      if file_size > 100.megabytes
        raise ConversionError, "File too large: #{file_size} bytes (max: 100MB)"
      end
    end
    
    def convert_to_markdown(file_path)
      Rails.logger.info "Converting #{file_path} to Markdown using MarkItDown"
      
      # Prepare Python command
      python_script = build_markitdown_command(file_path)
      
      # Execute with timeout and capture output
      result = nil
      exit_status = nil
      
      # Use Open3 for better subprocess control
      require 'open3'
      
      Open3.popen3(python_script) do |stdin, stdout, stderr, wait_thr|
        # Set timeout (5 minutes for large files)
        timeout = options[:timeout] || 300
        
        begin
          Timeout.timeout(timeout) do
            stdin.close  # We don't need to send input
            result = stdout.read
            error_output = stderr.read
            exit_status = wait_thr.value
            
            unless exit_status.success?
              raise ConversionError, "MarkItDown failed: #{error_output}"
            end
            
            if error_output.present?
              Rails.logger.warn "MarkItDown warnings: #{error_output}"
            end
          end
        rescue Timeout::Error
          Process.kill('KILL', wait_thr.pid)
          raise ConversionError, "MarkItDown conversion timed out after #{timeout} seconds"
        end
      end
      
      if result.blank?
        raise ConversionError, "MarkItDown returned empty content"
      end
      
      # CRITICAL: Sanitize null bytes for PostgreSQL compatibility
      # PostgreSQL cannot store null bytes in text fields
      sanitized_result = result.gsub("\0", '')
      
      if sanitized_result != result
        Rails.logger.warn "Removed #{result.count("\0")} null bytes from MarkItDown output"
      end
      
      Rails.logger.info "Successfully converted #{file_path} to #{sanitized_result.length} characters of Markdown"
      sanitized_result
    rescue StandardError => e
      Rails.logger.error "MarkItDown conversion failed: #{e.message}"
      raise ConversionError, "Failed to convert document: #{e.message}"
    end
    
    def build_markitdown_command(file_path)
      # Use Python directly with markitdown module
      # Assumes markitdown is installed: pip install markitdown
      escaped_path = Shellwords.escape(file_path)
      
      python_code = <<~PYTHON
        import sys
        from markitdown import MarkItDown
        
        try:
            md = MarkItDown()
            result = md.convert("#{file_path}")
            print(result.text_content)
        except Exception as e:
            print(f"Error: {e}", file=sys.stderr)
            sys.exit(1)
      PYTHON
      
      "python3 -c #{Shellwords.escape(python_code)}"
    end
    
    def estimate_tokens_accurately(content)
      # More sophisticated token estimation than simple chars/4
      # Account for Markdown structure and typical token patterns
      
      return 0 if content.blank?
      
      # Base character count
      char_count = content.length
      
      # Markdown-specific adjustments
      markdown_overhead = calculate_markdown_overhead(content)
      
      # Estimate tokens considering:
      # - Average English token is ~4 characters
      # - Markdown formatting adds overhead
      # - Code blocks are typically more token-dense
      # - Headers and lists have formatting tokens
      
      base_tokens = char_count / 4.0
      adjusted_tokens = base_tokens + markdown_overhead
      
      # Round up to be conservative
      adjusted_tokens.ceil
    end
    
    def calculate_markdown_overhead(content)
      overhead = 0
      
      # Count headers (# tokens)
      overhead += content.scan(/^#+\s/).length * 2
      
      # Count lists (bullet points add tokens)
      overhead += content.scan(/^[\s]*[-*+]\s/).length
      overhead += content.scan(/^[\s]*\d+\.\s/).length
      
      # Count code blocks (``` tokens)
      overhead += content.scan(/```/).length
      
      # Count inline code (`tokens`)
      overhead += content.scan(/`[^`]+`/).length
      
      # Count links and images ([text](url) pattern)
      overhead += content.scan(/\[[^\]]*\]\([^)]*\)/).length * 3
      
      # Count emphasis (*text* and **text**)
      overhead += content.scan(/\*[^*]+\*/).length
      overhead += content.scan(/\*\*[^*]+\*\*/).length
      
      # Tables have significant overhead
      table_rows = content.scan(/\|.*\|/).length
      overhead += table_rows * 3
      
      overhead
    end
    
    def route_extraction_model(estimated_tokens)
      Rails.logger.info "Routing decision for #{estimated_tokens} estimated tokens"
      
      if estimated_tokens <= TIER_1_LIMIT
        model = OpenaiConfig::SettingsManager.model_for('extraction')
        {
          status: 'tier_1',
          model: model,
          estimated_tokens: estimated_tokens,
          limit: TIER_1_LIMIT,
          reason: "Content fits in Tier 1 model (#{model})",
          cost_tier: 'standard'
        }
      elsif estimated_tokens <= TIER_2_LIMIT
        # For very large content, use the more capable mini model
        model = 'gpt-4.1-mini-2025-04-14'
        {
          status: 'tier_2',
          model: model,
          estimated_tokens: estimated_tokens,
          limit: TIER_2_LIMIT,
          reason: "Content requires Tier 2 model (#{model}) for large context",
          cost_tier: 'premium'
        }
      else
        {
          status: 'too_much_text',
          model: nil,
          estimated_tokens: estimated_tokens,
          limit: TIER_2_LIMIT,
          reason: "Content exceeds maximum token limit (#{TIER_2_LIMIT})",
          cost_tier: 'unsupported',
          suggestions: [
            'Split document into smaller sections',
            'Use document summarization first',
            'Process specific pages only'
          ]
        }
      end
    end
    
    def handle_error(error)
      Rails.logger.error "#{self.class} failed: #{error.message}"
      Rails.logger.error error.backtrace.join("\n") if Rails.env.development?
      
      {
        success: false,
        error: error.message,
        error_type: error.class.name,
        routing_info: { status: 'failed', reason: error.message },
        metadata: build_error_metadata(error)
      }
    end
    
    def build_error_metadata(error)
      {
        service: self.class.name,
        file_path: file_path,
        error_class: error.class.name,
        timestamp: Time.current.iso8601,
        file_exists: File.exist?(file_path),
        file_extension: File.exist?(file_path) ? File.extname(file_path) : nil,
        supported_formats: SUPPORTED_FORMATS
      }
    end
  end
end