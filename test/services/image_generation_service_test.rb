# frozen_string_literal: true

require 'test_helper'

class ImageGenerationServiceTest < ActiveSupport::TestCase
    
    def setup
      @valid_prompt = "A serene landscape with mountains"
    end
    
    test "initializes with valid prompt" do
      service = ImageGenerationService.new(prompt: @valid_prompt)
      assert_equal @valid_prompt, service.prompt
      assert_equal 'gpt-image-1', service.model  # Default to newest
      assert_equal 'high', service.quality  # Default quality for gpt-image-1
      assert_equal 1, service.n
      assert_equal 'url', service.response_format
    end
    
    test "validates prompt presence" do
      service = ImageGenerationService.new(prompt: "")
      result = service.call
      
      assert_not result[:success]
      assert_match /Prompt is required/, result[:error]
    end
    
    test "validates prompt length" do
      long_prompt = "a" * 4001
      service = ImageGenerationService.new(prompt: long_prompt)
      result = service.call
      
      assert_not result[:success]
      assert_match /Prompt too long/, result[:error]
    end
    
    test "accepts explicit model selection" do
      service = ImageGenerationService.new(
        prompt: @valid_prompt,
        model: 'dall-e-3'
      )
      
      assert_equal 'dall-e-3', service.model
      assert_equal 'hd', service.quality  # Default for dall-e-3
    end
    
    test "rejects unknown models" do
      assert_raises(ArgumentError) do
        ImageGenerationService.new(
          prompt: @valid_prompt,
          model: 'gpt-4-vision'  # Not an image generation model
        )
      end
    end
    
    test "validates quality options per model" do
      # gpt-image-1 with valid quality
      service = ImageGenerationService.new(
        prompt: @valid_prompt,
        model: 'gpt-image-1',
        quality: 'medium'
      )
      assert_equal 'medium', service.quality
      
      # dall-e-3 with its quality options
      service = ImageGenerationService.new(
        prompt: @valid_prompt,
        model: 'dall-e-3',
        quality: 'standard'
      )
      assert_equal 'standard', service.quality
    end
    
    test "validates size options per model" do
      # Valid size for gpt-image-1
      service = ImageGenerationService.new(
        prompt: @valid_prompt,
        model: 'gpt-image-1',
        size: '4096x4096'
      )
      assert_equal '4096x4096', service.size
      
      # Invalid size raises error
      assert_raises(ArgumentError) do
        ImageGenerationService.new(
          prompt: @valid_prompt,
          model: 'dall-e-2',
          size: '4096x4096'  # Not available for dall-e-2
        )
      end
    end
    
    test "enforces n=1 for models that don't support multiple" do
      service = ImageGenerationService.new(
        prompt: @valid_prompt,
        model: 'gpt-image-1',
        n: 5  # Should be forced to 1
      )
      assert_equal 1, service.n
      
      # dall-e-2 supports multiple
      service = ImageGenerationService.new(
        prompt: @valid_prompt,
        model: 'dall-e-2',
        n: 5
      )
      assert_equal 5, service.n
    end
    
    test "validates response format" do
      # Valid formats
      ['url', 'b64_json'].each do |format|
        service = ImageGenerationService.new(
          prompt: @valid_prompt,
          response_format: format
        )
        assert_equal format, service.response_format
      end
      
      # Invalid format
      assert_raises(ArgumentError) do
        ImageGenerationService.new(
          prompt: @valid_prompt,
          response_format: 'invalid'
        )
      end
    end
    
    test "includes metadata in response" do
      service = ImageGenerationService.new(prompt: @valid_prompt)
      
      # Mock the OPENAI client response
      mock_response = OpenStruct.new(
        data: [
          OpenStruct.new(
            url: 'https://example.com/image.png',
            b64_json: nil,
            revised_prompt: nil
          )
        ]
      )
      
      service.stub(:generate_content, mock_response) do
        result = service.call
        
        assert result[:success]
        assert result[:metadata]
        assert_equal 'gpt-image-1', result[:metadata][:model_used]
        assert_equal 'high', result[:metadata][:quality_used]
        assert_includes result[:metadata][:models_available], 'gpt-image-1'
        assert_includes result[:metadata][:models_available], 'dall-e-3'
        assert_includes result[:metadata][:models_available], 'dall-e-2'
      end
    end
    
    test "transforms response correctly" do
      service = ImageGenerationService.new(prompt: @valid_prompt)
      
      # Mock response with URL
      mock_response = OpenStruct.new(
        data: [
          OpenStruct.new(
            url: 'https://example.com/image.png',
            b64_json: nil,
            revised_prompt: 'Enhanced prompt by AI'
          )
        ]
      )
      
      service.stub(:generate_content, mock_response) do
        result = service.call
        
        assert result[:success]
        assert_equal 1, result[:count]
        assert_equal 'https://example.com/image.png', result[:images].first[:url]
        assert_equal 'Enhanced prompt by AI', result[:images].first[:revised_prompt]
        assert_nil result[:images].first[:b64_json]
      end
    end
    
    test "handles multiple images for dall-e-2" do
      service = ImageGenerationService.new(
        prompt: @valid_prompt,
        model: 'dall-e-2',
        n: 3
      )
      
      # Mock response with multiple images
      mock_response = OpenStruct.new(
        data: [
          OpenStruct.new(url: 'https://example.com/image1.png', b64_json: nil, revised_prompt: nil),
          OpenStruct.new(url: 'https://example.com/image2.png', b64_json: nil, revised_prompt: nil),
          OpenStruct.new(url: 'https://example.com/image3.png', b64_json: nil, revised_prompt: nil)
        ]
      )
      
      service.stub(:generate_content, mock_response) do
        result = service.call
        
        assert result[:success]
        assert_equal 3, result[:count]
        assert_equal 3, result[:images].size
      end
    end
end