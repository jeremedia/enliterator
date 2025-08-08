# OpenAI Configuration Guide

**Last Updated**: August 2025  
**Critical**: This document defines how OpenAI MUST be used in the Enliterator codebase.

## 🚨 ABSOLUTE RULES

1. **NEVER hardcode model names** - Always use `OpenaiConfig::SettingsManager`
2. **NEVER use outdated models** - No gpt-4o-2024-08-06, no gpt-3.5-turbo
3. **NEVER bypass the settings manager** - No direct OPENAI client calls for models
4. **ALWAYS check this document** - Before ANY OpenAI-related code changes

## OpenAI Ruby Gem (v0.16.0+)

**IMPORTANT**: We use the official OpenAI Ruby SDK gem, which may not be in your training data.

### ⚠️ CRITICAL: Research Before Implementation

**For ANY OpenAI feature not already in the codebase:**

1. **DO NOT TRUST TRAINING DATA** - APIs change rapidly
2. **ALWAYS CHECK THE GEM FIRST**:
   ```ruby
   # In Rails console, explore the actual API:
   OPENAI.methods.grep(/feature/)  # Find relevant methods
   OPENAI.feature.methods          # See what's available
   
   # Test with minimal call to see required parameters:
   begin
     OPENAI.feature.method_name(test: "param")
   rescue => e
     puts e.message  # Shows what's actually required
   end
   ```
3. **CHECK EXISTING SERVICES** - Someone may have already implemented it
4. **READ GEM SOURCE** if documentation is incomplete:
   - Run: `bundle open openai` (opens in editor)
   - Or check: `/Users/jeremy/.gem/ruby/3.4.4/gems/openai-0.16.0/lib/`

### Key Facts About the Gem

- **Gem Name**: `openai` (official SDK from OpenAI)
- **Version**: 0.16.0 or higher
- **Documentation**: https://gemdocs.org/gems/openai/0.16.0/
- **GitHub**: https://github.com/openai-ruby/openai-ruby

### Critical Differences from Training Data

The gem uses the **Responses API** with structured outputs, NOT the older chat completions pattern:

```ruby
# ✅ CORRECT - Modern Responses API (v0.16.0+)
OPENAI.responses.create(
  model: model,  # from SettingsManager!
  input: messages,
  text: ResponseModelClass  # Class inheriting from BaseModel
)

# ❌ WRONG - Old pattern (pre-v0.16.0)
OPENAI.chat.completions.create(...)  # Don't use this!
```

### Required Base Classes

All response models MUST inherit from:
```ruby
class YourResponse < OpenAI::Helpers::StructuredOutput::BaseModel
  required :field, String
  # Use OpenAI::ArrayOf[Type] for arrays
  # Use OpenAI::EnumOf[:option1, :option2] for enums
end
```

### If You're Unsure

1. Check the actual gem source: `bundle open openai`
2. Read the gem docs: https://gemdocs.org/gems/openai/0.16.0/
3. Look at existing services: `app/services/pools/entity_extraction_service.rb`
4. The gem's API differs from Python SDK - don't assume patterns

## Current Models (August 2025)

| Task | Model | Purpose |
|------|-------|---------|
| **Extraction** | `gpt-4.1` | Entity and term extraction with Structured Outputs |
| **Answer** | `gpt-4.1` | High-quality conversational responses |
| **Routing** | `gpt-4.1-nano` | Ultra-fast query routing and intent classification |
| **Fine-tuning** | `gpt-4.1-mini` | Base model for fine-tuning |

### ⚠️ OUTDATED MODELS - DO NOT USE
- ❌ `gpt-4o-2024-08-06` - Over a year old, expensive
- ❌ `gpt-4o-mini` - Outdated, replaced by gpt-4.1-mini
- ❌ `gpt-3.5-turbo` - Legacy model
- ❌ Any model with "2024" in the name

## Check Current Configuration

Use the `current_configuration` method to see what's actually configured:

```ruby
# In Rails console or code:
config = OpenaiConfig::SettingsManager.current_configuration

# Returns a hash like this (actual output from production):
{
  "timestamp": "2025-08-07T12:19:51Z",
  "models": {
    "extraction": "gpt-4.1",
    "answer": "gpt-4.1",
    "routing": "gpt-4.1-nano",
    "fine_tune": "gpt-4.1-mini"
  },
  "temperatures": {
    "extraction": 0.0,
    "answer": 0.7,
    "routing": 0.0
  },
  "settings_source": {
    "extraction": "database",    # Using database config
    "answer": "database",        # Using database config
    "routing": "database",       # Using database config
    "fine_tune": "database"      # Using database config
  },
  "environment_variables": {
    "OPENAI_MODEL": "gpt-4.1-2025-04-14",         # Set as fallback
    "OPENAI_MODEL_ANSWER": "gpt-4.1-2025-04-14",  # Set as fallback
    "OPENAI_FT_BASE": "gpt-4.1-mini-2025-04-14",  # Set as fallback
    "OPENAI_API_KEY": "SET (hidden)"              # API key is configured
  },
  "batch_api": {
    "enabled": true,
    "threshold": 10
  }
}
```

### Understanding settings_source

- **"database"** - Setting comes from database (via Admin UI) - PREFERRED
- **"environment"** - Setting comes from ENV variable (fallback)
- **"MISSING"** - No configuration found - WILL FAIL!

## The ONLY Correct Pattern

### ✅ CORRECT - Using Settings Manager

```ruby
# For extraction tasks - inherit from base service
class YourExtractionService < OpenaiConfig::BaseExtractionService
  def call
    # Model is automatically selected via SettingsManager
    # No need to specify model - base class handles it
    super
  end
  
  protected
  
  def response_model_class
    YourResponseClass  # Must inherit from correct base
  end
end

# Response models MUST use this base class
class YourResponseClass < OpenAI::Helpers::StructuredOutput::BaseModel
  required :field, String
  required :confidence, Float
end

# For any other OpenAI usage
model = OpenaiConfig::SettingsManager.model_for(:extraction)
temperature = OpenaiConfig::SettingsManager.temperature_for(:extraction)

# Never use the OPENAI client directly for model selection!
```

### ❌ WRONG - Direct API Usage

```ruby
# NEVER DO THIS - Hardcoded model
response = OPENAI.responses.create(
  model: "gpt-4.1",  # WRONG - hardcoded!
  messages: messages
)

# NEVER DO THIS - Old pattern
response = OPENAI.chat.completions.create(
  model: "gpt-4o-2024-08-06",  # WRONG - outdated and hardcoded!
  messages: messages
)

# NEVER DO THIS - ENV with fallback
model = ENV.fetch("OPENAI_MODEL", "gpt-4.1")  # WRONG - hardcoded fallback!
```

## Configuration Hierarchy

Models are resolved in this order:

1. **Database Settings** (via Admin UI at https://e.dev.domt.app/admin) - PREFERRED
2. **Environment Variables** (if database setting not found) - FALLBACK
3. **FAILURE** (no hardcoded defaults!) - INTENTIONAL

### Configure via Rails Console

```ruby
# Check current configuration
OpenaiConfig::SettingsManager.current_configuration

# Set models in database (preferred over ENV)
rails runner script/configure_openai_models.rb

# Or manually set individual settings:
OpenaiSetting.set('model_extraction', 'gpt-4.1', 
  category: 'model', 
  model_type: 'extraction',
  description: 'Model for entity extraction'
)

# Verify the change took effect
OpenaiConfig::SettingsManager.model_for(:extraction)
# => "gpt-4.1"
```

### Environment Variables (.env)

These are FALLBACKS only - database settings take precedence:

```bash
# Required
OPENAI_API_KEY=sk-...your-key...

# Model fallbacks (use specific dated versions)
OPENAI_MODEL=gpt-4.1-2025-04-14
OPENAI_MODEL_ANSWER=gpt-4.1-2025-04-14
OPENAI_FT_BASE=gpt-4.1-mini-2025-04-14
```

## Complete Service Implementation Example

```ruby
# app/services/document/analyzer_service.rb
class Document::AnalyzerService < OpenaiConfig::BaseExtractionService
  attr_reader :document_text, :analysis_type
  
  def initialize(document_text, analysis_type: :general)
    @document_text = document_text
    @analysis_type = analysis_type
  end
  
  protected
  
  # REQUIRED: Define your response model class
  def response_model_class
    DocumentAnalysisResponse
  end
  
  # REQUIRED: Provide the content to analyze
  def content_for_extraction
    document_text
  end
  
  # OPTIONAL: Build custom messages (default uses prompt templates)
  def build_messages
    [
      { role: :system, content: "Analyze this document for #{analysis_type} insights." },
      { role: :user, content: document_text }
    ]
  end
  
  # OPTIONAL: Transform the parsed result
  def transform_result(parsed_result)
    {
      success: true,
      summary: parsed_result.summary,
      key_points: parsed_result.key_points,
      metadata: extraction_metadata  # Includes model used, temperature, etc.
    }
  end
  
  # OPTIONAL: Validate inputs before processing
  def validate_inputs!
    raise ArgumentError, "Document text is required" if document_text.blank?
    raise ArgumentError, "Document too long" if document_text.length > 50_000
  end
end

# Response model - MUST inherit from this base class
class DocumentAnalysisResponse < OpenAI::Helpers::StructuredOutput::BaseModel
  required :summary, String, doc: "Brief summary of the document"
  required :key_points, OpenAI::ArrayOf[String], doc: "Main points extracted"
  required :sentiment, OpenAI::EnumOf[:positive, :neutral, :negative]
  required :confidence, Float, doc: "Confidence score 0-1"
end

# Usage:
service = Document::AnalyzerService.new("Your document text here...")
result = service.call
# => { success: true, summary: "...", key_points: [...], metadata: {...} }
```

## Non-Extraction Use Cases

### Embeddings (Different API)
```ruby
# Embeddings use a different API and don't need SettingsManager
text = "Text to embed"
response = OPENAI.embeddings.create(
  model: "text-embedding-3-small",  # Embedding models are fixed
  input: text
)
embedding_vector = response.data.first.embedding
```

### Conversational AI
```ruby
# Use the existing Literate::Engine, don't build your own
# It handles conversation state, context, and uses SettingsManager
```

## Service Implementation Checklist

When creating a new OpenAI service:

- [ ] Inherit from `OpenaiConfig::BaseExtractionService`
- [ ] Define response model inheriting from `OpenAI::Helpers::StructuredOutput::BaseModel`
- [ ] Implement `response_model_class` method (required)
- [ ] Implement `content_for_extraction` method (required)
- [ ] Never specify model directly - BaseExtractionService handles it
- [ ] Test with `OpenaiConfig::SettingsManager.current_configuration`

## Debugging Commands

```bash
# Check what's actually configured
rails console
pp OpenaiConfig::SettingsManager.current_configuration

# See which model would be used for extraction
OpenaiConfig::SettingsManager.model_for(:extraction)

# Check if database settings exist
OpenaiSetting.active.pluck(:key, :value)

# Find any hardcoded models in codebase
grep -r "gpt-4o-2024\|gpt-3.5\|gpt-4o-mini" app/ --include="*.rb"

# Test an extraction service
service = Pools::EntityExtractionService.new(content: "test")
result = service.call
puts result[:metadata]  # Should show model used
```

## Common Pitfalls

1. **Training data confusion**: Claude/GPT might suggest old patterns from training data
2. **Copy-paste from old code**: Always check for hardcoded models
3. **ENV fallbacks**: Don't add default values to `ENV.fetch()`
4. **Direct client usage**: Always use SettingsManager or BaseExtractionService
5. **Assuming models exist**: Always check `current_configuration` first

## Why This Architecture?

1. **Cost Control**: Centralized config prevents expensive model usage
2. **Easy Updates**: Change models in one place when new versions release
3. **Environment Flexibility**: Dev/staging/production can use different models
4. **No Surprises**: Explicit failure better than silent fallback to wrong model
5. **Audit Trail**: Database settings show who changed what and when

## Need Help?

- Implementation: `app/services/openai_config/settings_manager.rb`
- Base class: `app/services/openai_config/base_extraction_service.rb`  
- Examples: `app/services/pools/entity_extraction_service.rb`
- Tests: `rails test test/services/openai_config/`
- Admin UI: https://e.dev.domt.app/admin

---

**Remember**: When in doubt, check `OpenaiConfig::SettingsManager.current_configuration` to see what's actually being used!