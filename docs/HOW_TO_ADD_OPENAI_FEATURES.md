# How to Add New OpenAI Features: A Complete Research Guide

**Created**: August 2025  
**Purpose**: Document the COMPLETE process for adding OpenAI features using ALL available research methods

## 🚨 The Critical Lesson: Multiple Research Sources Required

**What went wrong in my first attempt:**
1. I tested the API empirically and found `dall-e-3` worked
2. I concluded it was the newest model
3. I was WRONG - `gpt-image-1` is the newest model (released with GPT-4o)
4. My testing missed it because I didn't check documentation or web sources

## The Complete Research Hierarchy

Use ALL of these, not just one:

### 1. 🌐 Web Research (Official Documentation)
```ruby
# Use WebSearch or WebFetch to get current documentation
WebSearch: "OpenAI API [feature] 2025 documentation"
WebFetch: "https://platform.openai.com/docs/guides/[feature]"

# Why: APIs change rapidly, new models are released frequently
# Example: gpt-image-1 wasn't in my training data OR initial testing
```

### 2. 💎 Gem Source Code
```ruby
# Explore the actual gem implementation
bundle open openai
# Or check: /Users/jeremy/.gem/ruby/3.4.4/gems/openai-0.16.0/

# Look for:
# - lib/openai/resources/[feature].rb
# - Method signatures
# - Parameter validation
# - Response structures
```

### 3. 🧪 Empirical Testing (Rails Console)
```ruby
# Test what actually works
rails console

# Discover available methods
OPENAI.methods.grep(/feature/)
api = OPENAI.feature
api.methods - Object.methods

# Test with minimal parameters
begin
  response = api.method_name(minimal_params)
  puts "Works! Response: #{response.class}"
rescue => e
  puts "Error shows requirements: #{e.message}"
end

# BUT REMEMBER: This only shows what exists, not what's newest/best!
```

### 4. 📚 Existing Codebase
```ruby
# Check if someone already implemented it
grep -r "feature_name" app/services/
# Look at existing patterns
```

### 5. 🚫 Training Data (NEVER TRUST)
- Assume it's outdated
- Only use for general patterns, not specifics

## Real Example: Image Generation Research (Corrected)

### Step 1: Web Research (SHOULD HAVE DONE FIRST)
```ruby
# Search for official docs
WebSearch: "OpenAI image generation API 2025"
# Result: gpt-image-1 is the newest model, not dall-e-3!
# - Supports up to 4096x4096 resolution
# - Better text rendering than DALL-E
# - Built on GPT-4o multimodal framework
```

### Step 2: Test in Console (Verify Documentation)
```ruby
# Test the documented model
response = OPENAI.images.generate(
  model: 'gpt-image-1',
  prompt: 'test',
  quality: 'high',
  size: '1024x1024'
)
# ✅ Works!

# Test documented quality levels
%w[low medium high].each do |quality|
  OPENAI.images.generate(model: 'gpt-image-1', prompt: 'test', quality: quality)
  puts "#{quality}: ✅"
end
```

### Step 3: Check Gem Implementation
```ruby
# In gem source: lib/openai/resources/images.rb
# Find actual method signatures
def generate(model:, prompt:, **params)
  # ... implementation
end
```

### Step 4: Document Findings
```ruby
# FINDINGS: Image Generation (August 2025)
# ========================================
# From Web Research:
#   - gpt-image-1: Newest model (GPT-4o based)
#   - dall-e-3: Previous generation
#   - dall-e-2: Legacy
#
# From Testing:
#   - All three models work
#   - gpt-image-1 supports quality: low/medium/high
#   - Sizes vary by model
#
# From Gem:
#   - Returns OpenAI::Models::ImagesResponse
#   - response.data[0].url contains image URL
#   - response.data[0].b64_json for base64
```

## The Correct Service Implementation

Based on COMPLETE research:

```ruby
module Ekn
  # Image generation service using gpt-image-1 (newest as of August 2025)
  # Research sources:
  #   - Web: https://platform.openai.com/docs/guides/image-generation
  #   - Testing: Verified in Rails console 2025-08-07
  #   - Gem: openai v0.16.0 supports all documented features
  class ImageGenerationService < ApplicationService
    
    # From documentation (not testing alone!)
    NEWEST_MODEL = 'gpt-image-1'.freeze
    FALLBACK_MODELS = ['dall-e-3', 'dall-e-2'].freeze
    
    # Quality options (from docs + verified by testing)
    QUALITIES = {
      'gpt-image-1' => ['low', 'medium', 'high'],
      'dall-e-3' => ['standard', 'hd'],
      'dall-e-2' => ['standard']
    }.freeze
    
    # Sizes (from docs, some not testable without specific accounts)
    SIZES = {
      'gpt-image-1' => ['1024x1024', '1024x1536', '1536x1024', '4096x4096'],
      'dall-e-3' => ['1024x1024', '1792x1024', '1024x1792'],
      'dall-e-2' => ['256x256', '512x512', '1024x1024']
    }.freeze
    
    def initialize(prompt:, model: nil, quality: nil)
      @prompt = prompt
      @model = select_model(model)
      @quality = select_quality(quality)
    end
    
    def call
      params = {
        model: @model,
        prompt: @prompt,
        quality: @quality,
        n: 1  # gpt-image-1 only supports 1
      }
      
      response = OPENAI.images.generate(**params)
      
      {
        success: true,
        url: response.data.first.url,
        b64_json: response.data.first.b64_json,
        model_used: @model,
        quality_used: @quality
      }
    rescue => e
      handle_error(e)
    end
    
    private
    
    def select_model(requested)
      # Try newest first, fall back if not available
      return NEWEST_MODEL if requested.nil?
      
      # Validate requested model
      all_models = [NEWEST_MODEL] + FALLBACK_MODELS
      return requested if all_models.include?(requested)
      
      raise ArgumentError, "Unknown model: #{requested}"
    end
    
    def select_quality(requested)
      return 'high' if requested.nil? && @model == 'gpt-image-1'
      return 'hd' if requested.nil? && @model == 'dall-e-3'
      return 'standard' if requested.nil?
      
      available = QUALITIES[@model]
      return requested if available&.include?(requested)
      
      available&.last || 'standard'
    end
    
    def handle_error(error)
      # Check if model not available (account limitations)
      if error.message.include?('model_not_found')
        # Try fallback model
        @model = FALLBACK_MODELS.first
        retry
      end
      
      {
        success: false,
        error: error.message
      }
    end
  end
end
```

## Research Checklist for New Features

### Before Writing ANY Code:

- [ ] **Web Research**: Search for official OpenAI docs for the feature
- [ ] **Check Release Notes**: Look for "OpenAI [feature] announcement 2025"
- [ ] **Read Gem Docs**: https://gemdocs.org/gems/openai/0.16.0/
- [ ] **Explore Gem Source**: `bundle open openai` to see actual implementation
- [ ] **Test in Console**: Verify what works with current credentials
- [ ] **Check Existing Code**: Has someone already implemented this?
- [ ] **Document Sources**: Note WHERE each piece of info came from

### During Implementation:

- [ ] **Cite Sources**: Add comments showing where info came from
- [ ] **Handle Fallbacks**: Newer features might not be available to all accounts
- [ ] **Test Multiple Scenarios**: What works vs what's documented
- [ ] **Update Documentation**: Add your findings to this guide

### Common Pitfalls:

1. **Testing alone isn't enough** - I found dall-e-3 worked but missed gpt-image-1
2. **Docs can be restricted** - Platform docs might 403, use web search
3. **Account limitations** - Your account might not have access to newest features
4. **Gem vs API mismatch** - Gem might not support latest API features yet

## Key Insight

**Testing shows what works. Documentation shows what's best.**

You need BOTH to implement correctly. Testing alone led me to use dall-e-3 when gpt-image-1 was available and superior.

## Update Log

- **2025-08-07**: Discovered gpt-image-1 through web research after initially missing it
- **2025-08-07**: Added web research as primary research method  
- **2025-08-07**: Corrected image generation service to use gpt-image-1
- **2025-08-07**: Successfully implemented ImageGenerationService at `/app/services/image_generation_service.rb`
- **2025-08-07**: All tests passing, service ready for production use

---

*Remember: Your training data is outdated. The gem might be outdated. Even your tests might miss things. Always start with current documentation.*