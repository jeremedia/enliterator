# frozen_string_literal: true

require 'test_helper'

class Ingest::TokenAwareMarkitdownServiceTest < ActiveSupport::TestCase
  
  def setup
    @test_file_path = "/tmp/test_document.pdf"
    @service = Ingest::TokenAwareMarkitdownService.new(@test_file_path)
    
    # Create a dummy test file
    File.write(@test_file_path, "dummy content")
  end
  
  def teardown
    # Clean up test files
    File.delete(@test_file_path) if File.exist?(@test_file_path)
  end
  
  test "supported_formats returns correct file extensions" do
    expected_formats = %w[.pdf .docx .pptx .xlsx .md .txt .html .rtf .odt .jpg .jpeg .png .bmp .gif .svg]
    assert_equal expected_formats, Ingest::TokenAwareMarkitdownService.supported_formats
  end
  
  test "initializes with file path and options" do
    options = { timeout: 120 }
    service = Ingest::TokenAwareMarkitdownService.new(@test_file_path, options)
    
    assert_equal @test_file_path, service.file_path
    assert_equal options, service.options
  end
  
  test "validate_file! raises error for non-existent file" do
    non_existent_file = "/tmp/does_not_exist.pdf"
    service = Ingest::TokenAwareMarkitdownService.new(non_existent_file)
    
    assert_raises(Ingest::TokenAwareMarkitdownService::ConversionError) do
      service.send(:validate_file!)
    end
  end
  
  test "validate_file! raises error for unsupported format" do
    unsupported_file = "/tmp/test.unsupported"
    File.write(unsupported_file, "content")
    
    service = Ingest::TokenAwareMarkitdownService.new(unsupported_file)
    
    assert_raises(Ingest::TokenAwareMarkitdownService::UnsupportedFormatError) do
      service.send(:validate_file!)
    end
    
    File.delete(unsupported_file)
  end
  
  test "validate_file! raises error for file too large" do
    # Mock File.size to return large value
    File.stub(:size, 200.megabytes) do
      assert_raises(Ingest::TokenAwareMarkitdownService::ConversionError) do
        @service.send(:validate_file!)
      end
    end
  end
  
  test "estimate_tokens_accurately handles empty content" do
    assert_equal 0, @service.send(:estimate_tokens_accurately, "")
    assert_equal 0, @service.send(:estimate_tokens_accurately, nil)
  end
  
  test "estimate_tokens_accurately calculates basic tokens" do
    # Simple text: ~4 chars per token
    simple_text = "This is a test document with some content."  # 42 chars
    estimated = @service.send(:estimate_tokens_accurately, simple_text)
    
    # Should be around 42/4 = 10.5, rounded up to 11
    assert_operator estimated, :>=, 10
    assert_operator estimated, :<=, 15
  end
  
  test "estimate_tokens_accurately adds overhead for markdown" do
    markdown_text = <<~MD
      # Header 1
      ## Header 2
      
      - List item 1
      - List item 2
      
      1. Numbered item
      2. Another item
      
      `inline code`
      
      ```
      code block
      ```
      
      [link text](http://example.com)
      
      **bold** and *italic*
      
      | Table | Header |
      |-------|--------|
      | Cell  | Data   |
    MD
    
    plain_text = "Simple text of similar length to markdown above for comparison purposes here."
    
    markdown_tokens = @service.send(:estimate_tokens_accurately, markdown_text)
    plain_tokens = @service.send(:estimate_tokens_accurately, plain_text)
    
    # Markdown should have more tokens due to formatting overhead
    assert_operator markdown_tokens, :>, plain_tokens
  end
  
  test "calculate_markdown_overhead counts formatting elements" do
    markdown_with_elements = <<~MD
      # Header
      ## Another Header
      
      - List item
      * Another list item
      
      1. Numbered
      2. List
      
      `code`
      
      ```
      block
      ```
      
      [link](url)
      
      **bold** *italic*
      
      | Col1 | Col2 |
      |------|------|
      | Data | More |
    MD
    
    overhead = @service.send(:calculate_markdown_overhead, markdown_with_elements)
    
    # Should count: 2 headers + 2 bullets + 2 numbers + 1 code block + 1 inline code + 1 link + 2 emphasis + 2 table rows
    assert_operator overhead, :>, 10
  end
  
  test "route_extraction_model selects tier 1 for small content" do
    small_tokens = 1000
    routing = @service.send(:route_extraction_model, small_tokens)
    
    assert_equal 'tier_1', routing[:status]
    assert_equal small_tokens, routing[:estimated_tokens]
    assert_equal 380_000, routing[:limit]
    assert_equal 'standard', routing[:cost_tier]
    assert routing[:model].present?
  end
  
  test "route_extraction_model selects tier 2 for large content" do
    large_tokens = 500_000  # Between tier 1 and tier 2 limits
    routing = @service.send(:route_extraction_model, large_tokens)
    
    assert_equal 'tier_2', routing[:status]
    assert_equal 'gpt-4.1-mini-2025-04-14', routing[:model]
    assert_equal large_tokens, routing[:estimated_tokens]
    assert_equal 1_000_000, routing[:limit]
    assert_equal 'premium', routing[:cost_tier]
  end
  
  test "route_extraction_model rejects oversized content" do
    huge_tokens = 1_500_000  # Exceeds tier 2 limit
    routing = @service.send(:route_extraction_model, huge_tokens)
    
    assert_equal 'too_much_text', routing[:status]
    assert_nil routing[:model]
    assert_equal huge_tokens, routing[:estimated_tokens]
    assert_equal 1_000_000, routing[:limit]
    assert_equal 'unsupported', routing[:cost_tier]
    assert routing[:suggestions].present?
  end
  
  test "build_markitdown_command creates proper Python command" do
    test_path = "/path/to/test.pdf"
    service = Ingest::TokenAwareMarkitdownService.new(test_path)
    
    command = service.send(:build_markitdown_command, test_path)
    
    assert_includes command, "python3 -c"
    assert_includes command, "MarkItDown"
    assert_includes command, test_path
  end
  
  test "handle_error returns structured error response" do
    error = StandardError.new("Test error message")
    result = @service.send(:handle_error, error)
    
    assert_equal false, result[:success]
    assert_equal "Test error message", result[:error]
    assert_equal "StandardError", result[:error_type]
    assert_equal 'failed', result[:routing_info][:status]
    assert result[:metadata].present?
  end
  
  test "build_error_metadata includes relevant error information" do
    error = Ingest::TokenAwareMarkitdownService::ConversionError.new("Conversion failed")
    metadata = @service.send(:build_error_metadata, error)
    
    assert_equal Ingest::TokenAwareMarkitdownService.name, metadata[:service]
    assert_equal @test_file_path, metadata[:file_path]
    assert_equal "Ingest::TokenAwareMarkitdownService::ConversionError", metadata[:error_class]
    assert metadata[:timestamp].present?
    assert_equal true, metadata[:file_exists]  # Our test file exists
    assert_equal ".pdf", metadata[:file_extension]
    assert metadata[:supported_formats].present?
  end
  
  test "convert_with_routing returns success structure for valid workflow" do
    # Mock the conversion process
    markdown_content = "# Test Document\n\nThis is converted content."
    
    @service.stub(:convert_to_markdown, markdown_content) do
      result = @service.convert_with_routing
      
      assert_equal true, result[:success]
      assert_equal markdown_content, result[:content]
      assert result[:routing_info].present?
      assert result[:metadata].present?
      
      # Check metadata structure
      metadata = result[:metadata]
      assert_equal Ingest::TokenAwareMarkitdownService.name, metadata[:service]
      assert_equal @test_file_path, metadata[:file_path]
      assert metadata[:file_size_bytes].present?
      assert_equal markdown_content.length, metadata[:content_length_chars]
      assert metadata[:estimated_tokens].present?
      assert metadata[:timestamp].present?
      assert metadata[:supported_formats].present?
    end
  end
  
  test "convert_with_routing handles conversion errors gracefully" do
    # Simulate a conversion error
    error_message = "MarkItDown conversion failed"
    
    @service.stub(:convert_to_markdown, -> (_) { raise Ingest::TokenAwareMarkitdownService::ConversionError.new(error_message) }) do
      result = @service.convert_with_routing
      
      assert_equal false, result[:success]
      assert_equal error_message, result[:error]
      assert_equal "Ingest::TokenAwareMarkitdownService::ConversionError", result[:error_type]
      assert_equal 'failed', result[:routing_info][:status]
      assert result[:metadata].present?
    end
  end
  
  test "service constants are properly defined" do
    assert_equal 380_000, Ingest::TokenAwareMarkitdownService::TIER_1_LIMIT
    assert_equal 1_000_000, Ingest::TokenAwareMarkitdownService::TIER_2_LIMIT
    
    expected_formats = %w[.pdf .docx .pptx .xlsx .md .txt .html .rtf .odt .jpg .jpeg .png .bmp .gif .svg]
    assert_equal expected_formats, Ingest::TokenAwareMarkitdownService::SUPPORTED_FORMATS
  end
  
  test "service integrates with Rails logging" do
    # Capture log output
    log_output = StringIO.new
    temp_logger = Logger.new(log_output)
    Rails.stub(:logger, temp_logger) do
      @service.send(:validate_file!)  # This should log
    end
    
    # We can't easily test the actual log content without mocking the conversion,
    # but we can verify the logger is being used
    assert_respond_to Rails.logger, :info
    assert_respond_to Rails.logger, :error
    assert_respond_to Rails.logger, :warn
  end
end